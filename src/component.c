#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jsmn.h"
#include "lua_plugin.h"
#include "vendor/lua/lauxlib.h"
#include "vendor/lua/lualib.h"

#define LUA_JSON_RECURSION_LIMIT 128

static char *pending_host_error = NULL;
static size_t pending_host_error_len = 0;

typedef struct {
  const char *json;
  jsmntok_t *tokens;
  int count;
} JsonDoc;

typedef struct {
  char *buf;
  size_t len;
  size_t cap;
} StrBuf;

static void sb_init(StrBuf *sb) {
  sb->buf = NULL;
  sb->len = 0;
  sb->cap = 0;
}

static void sb_free(StrBuf *sb) {
  if (sb->buf != NULL) {
    free(sb->buf);
    sb->buf = NULL;
  }
  sb->len = 0;
  sb->cap = 0;
}

static int sb_reserve(StrBuf *sb, size_t add_len) {
  size_t need;
  size_t next_cap;
  char *next_buf;
  if (add_len > (size_t)-1 - sb->len - 1u) {
    return 0;
  }
  need = sb->len + add_len + 1u;
  if (need <= sb->cap) {
    return 1;
  }
  next_cap = sb->cap == 0 ? 128u : sb->cap;
  while (next_cap < need) {
    if (next_cap > ((size_t)-1 / 2u)) {
      next_cap = need;
      break;
    }
    next_cap *= 2u;
  }
  next_buf = (char *)realloc(sb->buf, next_cap);
  if (next_buf == NULL) {
    return 0;
  }
  sb->buf = next_buf;
  sb->cap = next_cap;
  return 1;
}

static int sb_append_len(StrBuf *sb, const char *src, size_t len) {
  if (len == 0) {
    return 1;
  }
  if (!sb_reserve(sb, len)) {
    return 0;
  }
  memcpy(sb->buf + sb->len, src, len);
  sb->len += len;
  sb->buf[sb->len] = '\0';
  return 1;
}

static int sb_append_c(StrBuf *sb, char c) {
  if (!sb_reserve(sb, 1u)) {
    return 0;
  }
  sb->buf[sb->len++] = c;
  sb->buf[sb->len] = '\0';
  return 1;
}

static int str_ends_with(const char *s, const char *suffix) {
  size_t s_len = strlen(s);
  size_t suffix_len = strlen(suffix);
  if (suffix_len > s_len) {
    return 0;
  }
  return memcmp(s + (s_len - suffix_len), suffix, suffix_len) == 0;
}

static char *dup_with_optional_lua_suffix(const char *name, int add_lua_suffix) {
  size_t len = strlen(name);
  size_t extra = add_lua_suffix ? 4u : 0u;
  char *result = (char *)malloc(len + extra + 1u);
  if (result == NULL) {
    return NULL;
  }
  memcpy(result, name, len);
  if (add_lua_suffix) {
    memcpy(result + len, ".lua", 4u);
    len += 4u;
  }
  result[len] = '\0';
  return result;
}

static char *dup_dots_to_slashes(const char *name, int add_lua_suffix) {
  size_t len = strlen(name);
  size_t extra = add_lua_suffix ? 4u : 0u;
  char *result = (char *)malloc(len + extra + 1u);
  size_t i;
  if (result == NULL) {
    return NULL;
  }
  for (i = 0; i < len; i++) {
    result[i] = name[i] == '.' ? '/' : name[i];
  }
  if (add_lua_suffix) {
    memcpy(result + len, ".lua", 4u);
    len += 4u;
  }
  result[len] = '\0';
  return result;
}

static int str_equals(const char *a, const char *b) { return strcmp(a, b) == 0; }

static void set_component_string(lua_plugin_string_t *ret, const char *text,
                                 size_t len) {
  ret->ptr = NULL;
  ret->len = len;
  if (len > 0) {
    ret->ptr = (uint8_t *)malloc(len);
    if (ret->ptr == NULL) {
      ret->len = 0;
      return;
    }
    memcpy(ret->ptr, text, len);
  }
}

static void set_component_cstr(lua_plugin_string_t *ret, const char *text) {
  set_component_string(ret, text, strlen(text));
}

static int set_lua_error_string(lua_State *L, lua_plugin_string_t *err) {
  size_t len = 0;
  const char *msg = lua_tolstring(L, -1, &len);
  if (msg == NULL) {
    set_component_cstr(err, "lua error");
  } else {
    set_component_string(err, msg, len);
  }
  return 0;
}

static char json_null_registry_key;
static char json_object_metatable_registry_key;
static char json_array_metatable_registry_key;

static int json_encode_value(lua_State *L, int idx, StrBuf *out,
                             const void **seen, int seen_count, int depth);

static int lua_registry_value_equals(lua_State *L, int idx, const void *key) {
  int result;
  idx = lua_absindex(L, idx);
  lua_rawgetp(L, LUA_REGISTRYINDEX, key);
  result = lua_rawequal(L, idx, -1);
  lua_pop(L, 1);
  return result;
}

static int lua_is_json_null(lua_State *L, int idx) {
  return lua_registry_value_equals(L, idx, &json_null_registry_key);
}

static void lua_push_json_null(lua_State *L) {
  lua_rawgetp(L, LUA_REGISTRYINDEX, &json_null_registry_key);
}

static int json_table_has_metatable(lua_State *L, int idx, const void *key) {
  int result;
  idx = lua_absindex(L, idx);
  if (!lua_getmetatable(L, idx)) {
    return 0;
  }
  lua_rawgetp(L, LUA_REGISTRYINDEX, key);
  result = lua_rawequal(L, -2, -1);
  lua_pop(L, 2);
  return result;
}

static void json_set_table_metatable(lua_State *L, int idx, const void *key) {
  idx = lua_absindex(L, idx);
  lua_rawgetp(L, LUA_REGISTRYINDEX, key);
  lua_setmetatable(L, idx);
}

static int json_hex_val(char c) {
  if (c >= '0' && c <= '9') {
    return (int)(c - '0');
  }
  if (c >= 'a' && c <= 'f') {
    return 10 + (int)(c - 'a');
  }
  if (c >= 'A' && c <= 'F') {
    return 10 + (int)(c - 'A');
  }
  return -1;
}

static int json_parse_u16(const char *s, unsigned *out_cp) {
  int i;
  unsigned cp = 0;
  for (i = 0; i < 4; i++) {
    int h = json_hex_val(s[i]);
    if (h < 0) {
      return 0;
    }
    cp = (cp << 4) | (unsigned)h;
  }
  *out_cp = cp;
  return 1;
}

static int lua_add_utf8(luaL_Buffer *b, unsigned cp) {
  if (cp <= 0x7Fu) {
    luaL_addchar(b, (char)cp);
    return 1;
  }
  if (cp <= 0x7FFu) {
    luaL_addchar(b, (char)(0xC0u | ((cp >> 6) & 0x1Fu)));
    luaL_addchar(b, (char)(0x80u | (cp & 0x3Fu)));
    return 1;
  }
  if (cp <= 0xFFFFu) {
    luaL_addchar(b, (char)(0xE0u | ((cp >> 12) & 0x0Fu)));
    luaL_addchar(b, (char)(0x80u | ((cp >> 6) & 0x3Fu)));
    luaL_addchar(b, (char)(0x80u | (cp & 0x3Fu)));
    return 1;
  }
  if (cp <= 0x10FFFFu) {
    luaL_addchar(b, (char)(0xF0u | ((cp >> 18) & 0x07u)));
    luaL_addchar(b, (char)(0x80u | ((cp >> 12) & 0x3Fu)));
    luaL_addchar(b, (char)(0x80u | ((cp >> 6) & 0x3Fu)));
    luaL_addchar(b, (char)(0x80u | (cp & 0x3Fu)));
    return 1;
  }
  return 0;
}

static int lua_push_json_string_unescaped(lua_State *L, const char *s,
                                          size_t len) {
  luaL_Buffer b;
  size_t i = 0;
  luaL_buffinit(L, &b);
  while (i < len) {
    char c = s[i++];
    if (c != '\\') {
      luaL_addchar(&b, c);
      continue;
    }
    if (i >= len) {
      return luaL_error(L, "json.decode: invalid escape sequence");
    }
    c = s[i++];
    if (c == '"' || c == '\\' || c == '/') {
      luaL_addchar(&b, c);
    } else if (c == 'b') {
      luaL_addchar(&b, '\b');
    } else if (c == 'f') {
      luaL_addchar(&b, '\f');
    } else if (c == 'n') {
      luaL_addchar(&b, '\n');
    } else if (c == 'r') {
      luaL_addchar(&b, '\r');
    } else if (c == 't') {
      luaL_addchar(&b, '\t');
    } else if (c == 'u') {
      unsigned cp = 0;
      if (i + 4 > len || !json_parse_u16(s + i, &cp)) {
        return luaL_error(L, "json.decode: invalid unicode escape");
      }
      i += 4;
      if (cp >= 0xD800u && cp <= 0xDBFFu) {
        unsigned cp2 = 0;
        if (i + 6 <= len && s[i] == '\\' && s[i + 1] == 'u' &&
            json_parse_u16(s + i + 2, &cp2) && cp2 >= 0xDC00u &&
            cp2 <= 0xDFFFu) {
          cp = 0x10000u + ((cp - 0xD800u) << 10) + (cp2 - 0xDC00u);
          i += 6;
        }
      }
      if (!lua_add_utf8(&b, cp)) {
        return luaL_error(L, "json.decode: invalid unicode codepoint");
      }
    } else {
      return luaL_error(L, "json.decode: unsupported escape sequence");
    }
  }
  luaL_pushresult(&b);
  return 1;
}

static int json_decode_value(lua_State *L, const JsonDoc *doc, int tok_idx,
                             int depth, int *next_idx) {
  jsmntok_t tok;
  int i;
  int cur;
  if (depth > LUA_JSON_RECURSION_LIMIT) {
    return luaL_error(L, "json.decode: recursion limit exceeded");
  }
  if (tok_idx < 0 || tok_idx >= doc->count) {
    return luaL_error(L, "json.decode: token index out of range");
  }

  tok = doc->tokens[tok_idx];
  if (tok.type == JSMN_OBJECT) {
    lua_createtable(L, 0, tok.size);
    json_set_table_metatable(L, -1, &json_object_metatable_registry_key);
    cur = tok_idx + 1;
    for (i = 0; i < tok.size; i++) {
      jsmntok_t key_tok;
      if (cur >= doc->count) {
        return luaL_error(L, "json.decode: unexpected end of object");
      }
      key_tok = doc->tokens[cur++];
      if (key_tok.type != JSMN_STRING || key_tok.start < 0 ||
          key_tok.end < key_tok.start) {
        return luaL_error(L, "json.decode: object key must be string");
      }
      lua_push_json_string_unescaped(L, doc->json + key_tok.start,
                                     (size_t)(key_tok.end - key_tok.start));
      json_decode_value(L, doc, cur, depth + 1, &cur);
      lua_settable(L, -3);
    }
    *next_idx = cur;
    return 1;
  }

  if (tok.type == JSMN_ARRAY) {
    lua_createtable(L, tok.size, 0);
    json_set_table_metatable(L, -1, &json_array_metatable_registry_key);
    cur = tok_idx + 1;
    for (i = 0; i < tok.size; i++) {
      json_decode_value(L, doc, cur, depth + 1, &cur);
      lua_seti(L, -2, (lua_Integer)i + 1);
    }
    *next_idx = cur;
    return 1;
  }

  if (tok.type == JSMN_STRING) {
    if (tok.start < 0 || tok.end < tok.start) {
      return luaL_error(L, "json.decode: invalid string token");
    }
    lua_push_json_string_unescaped(L, doc->json + tok.start,
                                   (size_t)(tok.end - tok.start));
    *next_idx = tok_idx + 1;
    return 1;
  }

  if (tok.type == JSMN_PRIMITIVE) {
    size_t len;
    const char *p;
    if (tok.start < 0 || tok.end < tok.start) {
      return luaL_error(L, "json.decode: invalid primitive token");
    }
    len = (size_t)(tok.end - tok.start);
    p = doc->json + tok.start;
    if (len == 4 && memcmp(p, "true", 4u) == 0) {
      lua_pushboolean(L, 1);
    } else if (len == 5 && memcmp(p, "false", 5u) == 0) {
      lua_pushboolean(L, 0);
    } else if (len == 4 && memcmp(p, "null", 4u) == 0) {
      lua_push_json_null(L);
    } else {
      char small[128];
      char *tmp = small;
      size_t parsed;
      if (len + 1u > sizeof(small)) {
        tmp = (char *)malloc(len + 1u);
        if (tmp == NULL) {
          return luaL_error(L, "json.decode: out of memory");
        }
      }
      memcpy(tmp, p, len);
      tmp[len] = '\0';
      parsed = lua_stringtonumber(L, tmp);
      if (tmp != small) {
        free(tmp);
      }
      if (parsed == 0 || parsed != len + 1u) {
        return luaL_error(L, "json.decode: invalid numeric token");
      }
    }
    *next_idx = tok_idx + 1;
    return 1;
  }

  return luaL_error(L, "json.decode: unsupported token type");
}

static int push_json_decoded(lua_State *L, const char *json, size_t len) {
  JsonDoc doc;
  jsmn_parser parser;
  int rc;
  int next_idx = 0;

  doc.json = json;
  doc.tokens = NULL;
  doc.count = 0;

  jsmn_init(&parser);
  rc = jsmn_parse(&parser, json, len, NULL, 0);
  if (rc <= 0) {
    return luaL_error(L, "json.decode: invalid json input");
  }
  doc.count = rc;
  doc.tokens = (jsmntok_t *)malloc((size_t)doc.count * sizeof(jsmntok_t));
  if (doc.tokens == NULL) {
    return luaL_error(L, "json.decode: out of memory");
  }

  jsmn_init(&parser);
  rc = jsmn_parse(&parser, json, len, doc.tokens, (unsigned int)doc.count);
  if (rc < 1 || doc.tokens[0].type == JSMN_UNDEFINED) {
    free(doc.tokens);
    return luaL_error(L, "json.decode: invalid json input");
  }
  doc.count = rc;

  json_decode_value(L, &doc, 0, 0, &next_idx);
  if (next_idx != doc.count) {
    free(doc.tokens);
    return luaL_error(L, "json.decode: trailing tokens detected");
  }

  free(doc.tokens);
  return 1;
}

static int lua_json_decode(lua_State *L) {
  size_t len = 0;
  const char *json = luaL_checklstring(L, 1, &len);
  return push_json_decoded(L, json, len);
}

static int json_encode_string(StrBuf *out, const char *s, size_t len) {
  static const char hex[] = "0123456789abcdef";
  size_t i;
  if (!sb_append_c(out, '"')) {
    return 0;
  }
  for (i = 0; i < len; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c == '"') {
      if (!sb_append_len(out, "\\\"", 2u)) return 0;
    } else if (c == '\\') {
      if (!sb_append_len(out, "\\\\", 2u)) return 0;
    } else if (c == '\b') {
      if (!sb_append_len(out, "\\b", 2u)) return 0;
    } else if (c == '\f') {
      if (!sb_append_len(out, "\\f", 2u)) return 0;
    } else if (c == '\n') {
      if (!sb_append_len(out, "\\n", 2u)) return 0;
    } else if (c == '\r') {
      if (!sb_append_len(out, "\\r", 2u)) return 0;
    } else if (c == '\t') {
      if (!sb_append_len(out, "\\t", 2u)) return 0;
    } else if (c < 0x20u) {
      char esc[6];
      esc[0] = '\\';
      esc[1] = 'u';
      esc[2] = '0';
      esc[3] = '0';
      esc[4] = hex[(c >> 4) & 0x0Fu];
      esc[5] = hex[c & 0x0Fu];
      if (!sb_append_len(out, esc, sizeof(esc))) return 0;
    } else {
      if (!sb_append_c(out, (char)c)) return 0;
    }
  }
  return sb_append_c(out, '"');
}

static int json_table_shape(lua_State *L, int idx, lua_Integer *out_max,
                            int *out_is_array) {
  lua_Integer max_idx = 0;
  lua_Integer int_count = 0;
  int has_other = 0;
  idx = lua_absindex(L, idx);
  lua_pushnil(L);
  while (lua_next(L, idx) != 0) {
    if (lua_type(L, -2) == LUA_TNUMBER && lua_isinteger(L, -2)) {
      lua_Integer k = lua_tointeger(L, -2);
      if (k >= 1) {
        int_count++;
        if (k > max_idx) {
          max_idx = k;
        }
      } else {
        has_other = 1;
      }
    } else {
      has_other = 1;
    }
    lua_pop(L, 1);
  }
  *out_max = max_idx;
  *out_is_array = (!has_other && int_count == max_idx) ? 1 : 0;
  return 1;
}

static int json_resolve_table_shape(lua_State *L, int idx,
                                    lua_Integer *out_max,
                                    int *out_is_array) {
  int inferred_is_array = 0;
  lua_Integer inferred_max = 0;
  int marked_object = json_table_has_metatable(
      L, idx, &json_object_metatable_registry_key);
  int marked_array = json_table_has_metatable(
      L, idx, &json_array_metatable_registry_key);

  json_table_shape(L, idx, &inferred_max, &inferred_is_array);
  if (marked_object) {
    *out_max = 0;
    *out_is_array = 0;
    return 1;
  }
  if (marked_array) {
    if (!inferred_is_array) {
      return luaL_error(
          L, "json.encode: marked array must contain only dense positive integer keys");
    }
    *out_max = inferred_max;
    *out_is_array = 1;
    return 1;
  }
  *out_max = inferred_max;
  *out_is_array = inferred_is_array;
  return 1;
}

static int lua_json_object(lua_State *L) {
  if (lua_gettop(L) == 0 || lua_isnil(L, 1)) {
    lua_newtable(L);
  } else {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
  }
  json_set_table_metatable(L, -1, &json_object_metatable_registry_key);
  return 1;
}

static int lua_json_array(lua_State *L) {
  if (lua_gettop(L) == 0 || lua_isnil(L, 1)) {
    lua_newtable(L);
  } else {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
  }
  json_set_table_metatable(L, -1, &json_array_metatable_registry_key);
  return 1;
}

static int lua_json_is_object(lua_State *L) {
  lua_Integer max_idx = 0;
  int is_array = 0;
  if (!lua_istable(L, 1)) {
    lua_pushboolean(L, 0);
    return 1;
  }
  json_resolve_table_shape(L, 1, &max_idx, &is_array);
  lua_pushboolean(L, !is_array);
  return 1;
}

static int lua_json_is_array(lua_State *L) {
  lua_Integer max_idx = 0;
  int is_array = 0;
  if (!lua_istable(L, 1)) {
    lua_pushboolean(L, 0);
    return 1;
  }
  json_resolve_table_shape(L, 1, &max_idx, &is_array);
  lua_pushboolean(L, is_array);
  return 1;
}

static int json_encode_table(lua_State *L, int idx, StrBuf *out,
                             const void **seen, int seen_count, int depth) {
  const void *ptr;
  lua_Integer max_idx = 0;
  int is_array = 0;
  int i;
  idx = lua_absindex(L, idx);

  if (depth > LUA_JSON_RECURSION_LIMIT) {
    luaL_error(L, "json.encode: recursion limit exceeded");
    return 0;
  }
  ptr = lua_topointer(L, idx);
  for (i = 0; i < seen_count; i++) {
    if (seen[i] == ptr) {
      luaL_error(L, "json.encode: circular table reference");
      return 0;
    }
  }
  if (seen_count + 1 >= LUA_JSON_RECURSION_LIMIT) {
    luaL_error(L, "json.encode: nesting too deep");
    return 0;
  }
  seen[seen_count] = ptr;
  seen_count += 1;

  if (!json_resolve_table_shape(L, idx, &max_idx, &is_array)) {
    return 0;
  }
  if (is_array) {
    lua_Integer k;
    if (!sb_append_c(out, '[')) return 0;
    for (k = 1; k <= max_idx; k++) {
      if (k > 1 && !sb_append_c(out, ',')) return 0;
      lua_geti(L, idx, k);
      if (!json_encode_value(L, -1, out, seen, seen_count, depth + 1)) {
        lua_pop(L, 1);
        return 0;
      }
      lua_pop(L, 1);
    }
    return sb_append_c(out, ']');
  }

  if (!sb_append_c(out, '{')) return 0;
  i = 0;
  lua_pushnil(L);
  while (lua_next(L, idx) != 0) {
    size_t key_len = 0;
    const char *key;
    if (lua_type(L, -2) != LUA_TSTRING) {
      lua_pop(L, 2);
      luaL_error(L, "json.encode: object keys must be strings");
      return 0;
    }
    key = lua_tolstring(L, -2, &key_len);
    if (i++ > 0 && !sb_append_c(out, ',')) {
      lua_pop(L, 1);
      return 0;
    }
    if (!json_encode_string(out, key, key_len) || !sb_append_c(out, ':')) {
      lua_pop(L, 1);
      return 0;
    }
    if (!json_encode_value(L, -1, out, seen, seen_count, depth + 1)) {
      lua_pop(L, 1);
      return 0;
    }
    lua_pop(L, 1);
  }
  return sb_append_c(out, '}');
}

static int json_encode_value(lua_State *L, int idx, StrBuf *out,
                             const void **seen, int seen_count, int depth) {
  int t;
  if (lua_is_json_null(L, idx)) {
    return sb_append_len(out, "null", 4u);
  }
  t = lua_type(L, idx);
  if (t == LUA_TNIL) {
    return sb_append_len(out, "null", 4u);
  }
  if (t == LUA_TBOOLEAN) {
    return lua_toboolean(L, idx) ? sb_append_len(out, "true", 4u)
                                 : sb_append_len(out, "false", 5u);
  }
  if (t == LUA_TNUMBER) {
    char num[64];
    int n;
    if (lua_isinteger(L, idx)) {
      lua_Integer v = lua_tointeger(L, idx);
      n = snprintf(num, sizeof(num), "%lld", (long long)v);
    } else {
      lua_Number d = lua_tonumber(L, idx);
      if (!isfinite((double)d)) {
        luaL_error(L, "json.encode: non-finite numbers are not supported");
        return 0;
      }
      n = snprintf(num, sizeof(num), "%.17g", (double)d);
    }
    if (n <= 0 || (size_t)n >= sizeof(num)) {
      luaL_error(L, "json.encode: failed to format number");
      return 0;
    }
    return sb_append_len(out, num, (size_t)n);
  }
  if (t == LUA_TSTRING) {
    size_t len = 0;
    const char *s = lua_tolstring(L, idx, &len);
    return json_encode_string(out, s, len);
  }
  if (t == LUA_TTABLE) {
    return json_encode_table(L, idx, out, seen, seen_count, depth);
  }
  luaL_error(L, "json.encode: unsupported lua type: %s", lua_typename(L, t));
  return 0;
}

static int lua_json_encode(lua_State *L) {
  StrBuf out;
  const void *seen[LUA_JSON_RECURSION_LIMIT];
  sb_init(&out);
  if (!json_encode_value(L, 1, &out, seen, 0, 0)) {
    sb_free(&out);
    return luaL_error(L, "json.encode: out of memory");
  }
  lua_pushlstring(L, out.buf != NULL ? out.buf : "", out.len);
  sb_free(&out);
  return 1;
}

static int bytes_contains_literal(const char *s, size_t s_len, const char *needle) {
  size_t needle_len = strlen(needle);
  size_t i;
  if (needle_len == 0) {
    return 1;
  }
  if (needle_len > s_len) {
    return 0;
  }
  for (i = 0; i <= s_len - needle_len; i++) {
    if (memcmp(s + i, needle, needle_len) == 0) {
      return 1;
    }
  }
  return 0;
}

static int lua_table_field_count(lua_State *L, int idx) {
  int count = 0;
  idx = lua_absindex(L, idx);
  lua_pushnil(L);
  while (lua_next(L, idx) != 0) {
    count++;
    lua_pop(L, 1);
  }
  return count;
}

static int lua_host_raw_call(lua_State *L) {
  size_t target_len = 0;
  size_t args_len = 0;
  const char *target = luaL_checklstring(L, 1, &target_len);
  const char *args = "";
  lua_plugin_string_t target_string;
  lua_plugin_string_t args_string;
  lua_plugin_string_t ret;
  lua_plugin_string_t err;

  if (lua_gettop(L) >= 2 && !lua_isnil(L, 2)) {
    args = luaL_checklstring(L, 2, &args_len);
  }

  target_string.ptr = (uint8_t *)target;
  target_string.len = target_len;
  args_string.ptr = (uint8_t *)args;
  args_string.len = args_len;
  memset(&ret, 0, sizeof(ret));
  memset(&err, 0, sizeof(err));

  if (!gams_runtime_runtime_call(&target_string, &args_string, &ret, &err)) {
    const char *message = err.ptr != NULL ? (const char *)err.ptr : "host.call failed";
    size_t message_len = err.len > 0 ? err.len : 16u;
    lua_pushlstring(L, message, message_len);
    free(err.ptr);
    return lua_error(L);
  }

  lua_pushlstring(L, (const char *)(ret.ptr != NULL ? ret.ptr : (uint8_t *)""), ret.len);
  free(ret.ptr);
  return 1;
}

static int lua_host_call(lua_State *L) {
  int top = lua_gettop(L);
  int arg_count;
  int table_idx;
  int i;
  StrBuf encoded_args;
  const void *seen[LUA_JSON_RECURSION_LIMIT];
  size_t raw_len = 0;
  const char *raw;
  int has_ok_key;
  int has_err_key;

  luaL_checkstring(L, 1);
  arg_count = top > 1 ? top - 1 : 0;
  lua_createtable(L, arg_count, 0);
  table_idx = lua_gettop(L);
  for (i = 2; i <= top; i++) {
    lua_pushvalue(L, i);
    lua_seti(L, table_idx, (lua_Integer)i - 1);
  }

  sb_init(&encoded_args);
  if (!json_encode_value(L, table_idx, &encoded_args, seen, 0, 0)) {
    sb_free(&encoded_args);
    return luaL_error(L, "host.call: failed to encode arguments");
  }
  lua_pop(L, 1);

  if (encoded_args.len == 0) {
    lua_pushliteral(L, "[]");
  } else {
    lua_pushlstring(L, encoded_args.buf, encoded_args.len);
  }
  sb_free(&encoded_args);
  lua_replace(L, 2);
  lua_settop(L, 2);

  lua_host_raw_call(L);
  raw = lua_tolstring(L, -1, &raw_len);
  has_ok_key = bytes_contains_literal(raw, raw_len, "\"ok\"");
  has_err_key = bytes_contains_literal(raw, raw_len, "\"err\"");

  push_json_decoded(L, raw, raw_len);
  lua_remove(L, -2);

  if (lua_istable(L, -1)) {
    int field_count = lua_table_field_count(L, -1);
    if (has_err_key && field_count == 1) {
      lua_getfield(L, -1, "err");
      if (!lua_isnil(L, -1)) {
        return lua_error(L);
      }
      lua_pop(L, 1);
      return luaL_error(L, "host.call failed");
    }

    if (has_ok_key && field_count <= 1) {
      if (field_count == 0) {
        lua_pop(L, 1);
        lua_pushnil(L);
        return 1;
      }
      lua_getfield(L, -1, "ok");
      lua_remove(L, -2);
      return 1;
    }
  }

  return 1;
}

static int preopen_path_matches(const lua_plugin_string_t *preopen_path,
                                const char *path, size_t path_len,
                                size_t *relative_offset) {
  if (preopen_path->len == 1 && preopen_path->ptr[0] == '/') {
    *relative_offset = path_len > 0 && path[0] == '/' ? 1u : 0u;
    return 1;
  }
  if (path_len < preopen_path->len) {
    return 0;
  }
  if (memcmp(path, preopen_path->ptr, preopen_path->len) != 0) {
    return 0;
  }
  if (path_len == preopen_path->len) {
    *relative_offset = path_len;
    return 1;
  }
  if (path[preopen_path->len] != '/') {
    return 0;
  }
  *relative_offset = preopen_path->len + 1u;
  return 1;
}

static int try_fs_read_candidate(const char *candidate, uint8_t **out_data,
                                 size_t *out_len) {
  size_t candidate_len = strlen(candidate);
  wasi_filesystem_preopens_list_tuple2_own_descriptor_string_t preopens;
  size_t best = (size_t)-1;
  size_t best_prefix_len = 0;
  size_t best_relative_offset = 0;
  size_t i;
  wasi_filesystem_types_own_descriptor_t file;
  wasi_filesystem_types_error_code_t code = 0;
  lua_plugin_string_t relative;
  StrBuf out;
  uint64_t offset = 0;

  wasi_filesystem_preopens_get_directories(&preopens);
  for (i = 0; i < preopens.len; i++) {
    lua_plugin_string_t *preopen_path = &preopens.ptr[i].f1;
    size_t relative_offset = 0;
    if (preopen_path_matches(preopen_path, candidate, candidate_len, &relative_offset) &&
        preopen_path->len >= best_prefix_len) {
      best = i;
      best_prefix_len = preopen_path->len;
      best_relative_offset = relative_offset;
    }
  }
  if (best == (size_t)-1 && preopens.len > 0 && candidate_len > 0 && candidate[0] != '/') {
    best = 0;
    best_relative_offset = 0;
  }
  if (best == (size_t)-1) {
    wasi_filesystem_preopens_list_tuple2_own_descriptor_string_free(&preopens);
    return 0;
  }

  relative.ptr = (uint8_t *)(candidate + best_relative_offset);
  relative.len = candidate_len - best_relative_offset;
  if (!wasi_filesystem_types_method_descriptor_open_at(
          wasi_filesystem_types_borrow_descriptor(preopens.ptr[best].f0), 0, &relative, 0,
          WASI_FILESYSTEM_TYPES_DESCRIPTOR_FLAGS_READ, &file, &code)) {
    wasi_filesystem_preopens_list_tuple2_own_descriptor_string_free(&preopens);
    return 0;
  }

  sb_init(&out);
  for (;;) {
    lua_plugin_tuple2_list_u8_bool_t chunk;
    memset(&chunk, 0, sizeof(chunk));
    if (!wasi_filesystem_types_method_descriptor_read(
            wasi_filesystem_types_borrow_descriptor(file), 65536, offset, &chunk, &code)) {
      sb_free(&out);
      wasi_filesystem_types_descriptor_drop_own(file);
      wasi_filesystem_preopens_list_tuple2_own_descriptor_string_free(&preopens);
      return -1;
    }
    if (!sb_append_len(&out, (const char *)chunk.f0.ptr, chunk.f0.len)) {
      lua_plugin_list_u8_free(&chunk.f0);
      sb_free(&out);
      wasi_filesystem_types_descriptor_drop_own(file);
      wasi_filesystem_preopens_list_tuple2_own_descriptor_string_free(&preopens);
      return -1;
    }
    offset += chunk.f0.len;
    int done = chunk.f1 || chunk.f0.len == 0;
    lua_plugin_list_u8_free(&chunk.f0);
    if (done) {
      break;
    }
  }

  wasi_filesystem_types_descriptor_drop_own(file);
  wasi_filesystem_preopens_list_tuple2_own_descriptor_string_free(&preopens);
  *out_data = (uint8_t *)out.buf;
  *out_len = out.len;
  return 1;
}

static int lua_require_fs_searcher(lua_State *L) {
  const char *module_name = luaL_checkstring(L, 1);
  uint8_t *file_data = NULL;
  size_t file_len = 0;
  StrBuf err;
  char *candidates[4] = {0};
  int candidate_count = 0;
  int has_dot = strchr(module_name, '.') != NULL;
  int has_lua_suffix = str_ends_with(module_name, ".lua");
  int i;

  sb_init(&err);

  candidates[candidate_count++] = dup_with_optional_lua_suffix(module_name, 0);
  if (!has_lua_suffix) {
    candidates[candidate_count++] = dup_with_optional_lua_suffix(module_name, 1);
  }
  if (has_dot) {
    candidates[candidate_count++] = dup_dots_to_slashes(module_name, 0);
    if (!has_lua_suffix) {
      candidates[candidate_count++] = dup_dots_to_slashes(module_name, 1);
    }
  }

  for (i = 0; i < candidate_count; i++) {
    int duplicate = 0;
    int read_status;
    int j;
    if (candidates[i] == NULL) {
      sb_free(&err);
      for (j = 0; j < candidate_count; j++) {
        free(candidates[j]);
      }
      return luaL_error(L, "require searcher: out of memory");
    }
    for (j = 0; j < i; j++) {
      if (candidates[j] != NULL && str_equals(candidates[j], candidates[i])) {
        duplicate = 1;
        break;
      }
    }
    if (duplicate) {
      continue;
    }

    read_status = try_fs_read_candidate(candidates[i], &file_data, &file_len);
    if (read_status < 0) {
      sb_free(&err);
      for (j = 0; j < candidate_count; j++) {
        free(candidates[j]);
      }
      return luaL_error(L, "require searcher: fs.read transport failed");
    }
    if (read_status > 0) {
      int load_status = luaL_loadbufferx(L, (const char *)file_data, file_len,
                                         candidates[i], "t");
      char *resolved = candidates[i];
      free(file_data);
      for (j = 0; j < candidate_count; j++) {
        if (j != i) {
          free(candidates[j]);
        }
      }
      if (load_status != LUA_OK) {
        free(resolved);
        sb_free(&err);
        return lua_error(L);
      }
      lua_pushstring(L, resolved);
      free(resolved);
      sb_free(&err);
      return 2;
    }

    if (!sb_append_len(&err, "\n\tno file '", 11u) ||
        !sb_append_len(&err, candidates[i], strlen(candidates[i])) ||
        !sb_append_c(&err, '\'')) {
      sb_free(&err);
      for (j = 0; j < candidate_count; j++) {
        free(candidates[j]);
      }
      return luaL_error(L, "require searcher: out of memory");
    }
  }

  for (i = 0; i < candidate_count; i++) {
    free(candidates[i]);
  }

  lua_pushlstring(L, err.buf != NULL ? err.buf : "\n\tno file", err.len);
  sb_free(&err);
  return 1;
}

static void register_json_shape_metatable(lua_State *L, const void *key) {
  lua_newtable(L);
  lua_pushboolean(L, 0);
  lua_setfield(L, -2, "__metatable");
  lua_pushvalue(L, -1);
  lua_rawsetp(L, LUA_REGISTRYINDEX, key);
  lua_pop(L, 1);
}

static void register_json_lib(lua_State *L) {
  register_json_shape_metatable(L, &json_object_metatable_registry_key);
  register_json_shape_metatable(L, &json_array_metatable_registry_key);

  lua_newtable(L);
  lua_pushcfunction(L, lua_json_decode);
  lua_setfield(L, -2, "decode");
  lua_pushcfunction(L, lua_json_encode);
  lua_setfield(L, -2, "encode");
  lua_pushcfunction(L, lua_json_object);
  lua_setfield(L, -2, "object");
  lua_pushcfunction(L, lua_json_array);
  lua_setfield(L, -2, "array");
  lua_pushcfunction(L, lua_json_is_object);
  lua_setfield(L, -2, "is_object");
  lua_pushcfunction(L, lua_json_is_array);
  lua_setfield(L, -2, "is_array");
  lua_newtable(L);
  lua_pushvalue(L, -1);
  lua_rawsetp(L, LUA_REGISTRYINDEX, &json_null_registry_key);
  lua_setfield(L, -2, "null");
  lua_setglobal(L, "json");
}

static int lua_fs_read_text(lua_State *L) {
  size_t path_len = 0;
  const char *path = luaL_checklstring(L, 1, &path_len);
  char *path_z;
  uint8_t *file_data = NULL;
  size_t file_len = 0;
  int read_status;

  if (memchr(path, '\0', path_len) != NULL) {
    return luaL_error(L, "fs.read_text path must not contain NUL");
  }

  path_z = (char *)malloc(path_len + 1u);
  if (path_z == NULL) {
    return luaL_error(L, "fs.read_text: out of memory");
  }
  memcpy(path_z, path, path_len);
  path_z[path_len] = '\0';

  read_status = try_fs_read_candidate(path_z, &file_data, &file_len);

  if (read_status < 0) {
    lua_pushfstring(L, "fs.read_text failed for '%s': transport failed", path_z);
    free(path_z);
    return lua_error(L);
  }
  if (read_status == 0) {
    lua_pushfstring(L, "fs.read_text failed for '%s': file not found or not readable", path_z);
    free(path_z);
    return lua_error(L);
  }

  free(path_z);
  lua_pushlstring(L, (const char *)(file_data != NULL ? file_data : (uint8_t *)""), file_len);
  free(file_data);
  return 1;
}

static void register_fs_lib(lua_State *L) {
  lua_newtable(L);
  lua_pushcfunction(L, lua_fs_read_text);
  lua_setfield(L, -2, "read_text");
  lua_pushcfunction(L, lua_fs_read_text);
  lua_setfield(L, -2, "read");
  lua_setglobal(L, "fs");
}

static void register_host_lib(lua_State *L) {
  lua_newtable(L);
  lua_pushcfunction(L, lua_host_call);
  lua_setfield(L, -2, "call");
  lua_pushcfunction(L, lua_host_raw_call);
  lua_setfield(L, -2, "raw_call");
  lua_setglobal(L, "host");
}

static void configure_package_searchers(lua_State *L) {
  lua_getglobal(L, "package");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    luaL_error(L, "package table missing");
    return;
  }

  lua_getfield(L, -1, "searchers");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 2);
    luaL_error(L, "package.searchers missing");
    return;
  }

  lua_newtable(L);
  lua_geti(L, -2, 1);
  lua_seti(L, -2, 1);
  lua_pushcfunction(L, lua_require_fs_searcher);
  lua_seti(L, -2, 2);
  lua_setfield(L, -3, "searchers");
  lua_pushliteral(L, "");
  lua_setfield(L, -2, "path");
  lua_pushliteral(L, "");
  lua_setfield(L, -2, "cpath");
  lua_pop(L, 2);
}

static void open_lua_libs(lua_State *L) {
  luaL_requiref(L, "_G", luaopen_base, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_COLIBNAME, luaopen_coroutine, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_TABLIBNAME, luaopen_table, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_STRLIBNAME, luaopen_string, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_MATHLIBNAME, luaopen_math, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_UTF8LIBNAME, luaopen_utf8, 1);
  lua_pop(L, 1);
  luaL_requiref(L, LUA_LOADLIBNAME, luaopen_package, 1);
  lua_pop(L, 1);
  register_json_lib(L);
  register_fs_lib(L);
  register_host_lib(L);
  configure_package_searchers(L);
}

static int run_script(lua_State *L, const uint8_t *code, size_t code_len) {
  int status = luaL_loadbufferx(L, (const char *)code, code_len, "=(input)", "t");
  if (status != LUA_OK) {
    return status;
  }
  status = lua_pcall(L, 0, 0, 0);
  if (status != LUA_OK) {
    return status;
  }

  lua_getglobal(L, "main");
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    lua_pushnil(L);
    return LUA_OK;
  }
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 1);
    lua_pushliteral(L, "global 'main' exists but is not a function");
    return LUA_ERRRUN;
  }
  status = lua_pcall(L, 0, 1, 0);
  if (status != LUA_OK) {
    return status;
  }
  if (pending_host_error != NULL || pending_host_error_len > 0) {
    lua_pushlstring(L,
                    pending_host_error != NULL ? pending_host_error : "host.call failed",
                    pending_host_error_len > 0 ? pending_host_error_len : 16u);
    return LUA_ERRRUN;
  }
  return LUA_OK;
}

static int encode_return_value(lua_State *L, lua_plugin_string_t *ret) {
  if (lua_isstring(L, -1)) {
    size_t len = 0;
    const char *value = lua_tolstring(L, -1, &len);
    set_component_string(ret, value, len);
    return 1;
  }

  StrBuf out;
  const void *seen[LUA_JSON_RECURSION_LIMIT];
  sb_init(&out);
  if (!json_encode_value(L, -1, &out, seen, 0, 0)) {
    sb_free(&out);
    set_component_cstr(ret, "");
    return 0;
  }
  set_component_string(ret, out.buf != NULL ? out.buf : "null", out.len);
  sb_free(&out);
  return 1;
}

bool exports_gams_lua_lua_run(lua_plugin_string_t *source, lua_plugin_string_t *ret,
                              lua_plugin_string_t *err) {
  lua_State *L;
  int status;

  memset(ret, 0, sizeof(*ret));
  memset(err, 0, sizeof(*err));

  free(pending_host_error);
  pending_host_error = NULL;
  pending_host_error_len = 0;

  L = luaL_newstate();
  if (L == NULL) {
    set_component_cstr(err, "failed to create lua state");
    return false;
  }

  open_lua_libs(L);

  status = run_script(L, source->ptr, source->len);
  if (status != LUA_OK) {
    set_lua_error_string(L, err);
    lua_close(L);
    return false;
  }

  if (!encode_return_value(L, ret)) {
    set_component_cstr(err, "failed to encode lua return value");
    lua_close(L);
    return false;
  }

  lua_close(L);
  return true;
}
