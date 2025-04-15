--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--[[
This plugin allows to return a custom response, based on a trigger condition(s).

NB: some operations must be performed in specific phases, because NGiNX APIs
are otherwise disabled.
]]

local plugin_name        = "error-page-advanced"
local plugin_description = [[
This plugin allows to return a custom error page,
overriding APISIX/OpenResty defaults.
]]
local plugin_author      = {
  username = "mikyll",
  url = "https://github.com/mikyll",
}


local ngx             = ngx
local core            = require("apisix.core")
local apisix_plugin   = require("apisix.plugin")
local apisix_utils    = require("apisix.core.utils")

-- TODO: add error_range for other pages

local error_schema    = {
  description = "Error page to return when APISIX returns a specific status codes.",
  type = "object",
  additionalProperties = false,
  oneOf = {
    { required = { "redirect_url" } },
    { required = { "body" } },
  },
  properties = {
    body = {
      description = "Response body.",
      type = "string"
    },
    ["content-type"] = {
      description = "Response content type.",
      type = "string",
    },
    redirect_url = {
      description = "URL to redirect the request to.",
      type = "string",
    },
  },
}

local metadata_schema = {
  type = "object",
  additionalProperties = false,
  patternProperties = {
    ["^error_[2-5]{1}[0-9]{2}$"] = error_schema,
  },
  properties = {
    id = plugin_name,
    enable = {
      description = "Wheter the plugin is enabled or not.",
      type = "boolean",
      default = true,
    },
    set_content_length = {
      description = "If true automatically set the Content-Length header. If set to false, removes the header.",
      type = "boolean",
      default = true,
    },
  },
}

local schema          = {
  type = "object",
  properties = {},
}

local _M              = {
  version = 0.1,
  priority = 0,
  name = plugin_name,
  schema = schema,
  metadata_schema = metadata_schema,
  description = plugin_description,
  author = plugin_author,
}

-- Reference: https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
local status_text     = {
  ["100"] = "Continue",
  ["101"] = "Switching Protocols",
  ["102"] = "Processing",
  ["103"] = "Early Hints",

  ["200"] = "OK",
  ["201"] = "Created",
  ["202"] = "Accepted",
  ["203"] = "Non-Authoritative Information",
  ["204"] = "No Content",
  ["205"] = "Reset Content",
  ["206"] = "Partial Content",
  ["207"] = "Multi-Status",
  ["208"] = "Already Reported",
  ["226"] = "IM Used",

  ["300"] = "Multiple Choices",
  ["301"] = "Moved Permanently",
  ["302"] = "Found",
  ["303"] = "See Other",
  ["304"] = "Not Modified",
  ["305"] = "Use Proxy",
  ["307"] = "Temporary Redirect",
  ["308"] = "Permanent Redirect",

  ["400"] = "Bad Request",
  ["401"] = "Unauthorized",
  ["402"] = "Payment Required",
  ["403"] = "Forbidden",
  ["404"] = "Not Found",
  ["405"] = "Method Not Allowed",
  ["406"] = "Not Acceptable",
  ["407"] = "Proxy Authentication Required",
  ["408"] = "Request Timeout",
  ["409"] = "Conflict",
  ["410"] = "Gone",
  ["411"] = "Length Required",
  ["412"] = "Precondition Failed",
  ["413"] = "Content Too Large",
  ["414"] = "URI Too Long",
  ["415"] = "Unsupported Media Type",
  ["416"] = "Range Not Satisfiable",
  ["417"] = "Expectation Failed",
  ["418"] = "I'm a teapot",
  ["421"] = "Misdirected Request",
  ["422"] = "Unprocessable Content",
  ["423"] = "Locked",
  ["424"] = "Failed Dependency",
  ["425"] = "Too Early",
  ["426"] = "Upgrade Required",
  ["428"] = "Precondition Required",
  ["429"] = "Too Many Requests",
  ["431"] = "Request Header Fields Too Large",
  ["451"] = "Unavailable For Legal Reasons",

  ["500"] = "Internal Server Error",
  ["501"] = "Not Implemented",
  ["502"] = "Bad Gateway",
  ["503"] = "Service Unavailable",
  ["504"] = "Gateway Timeout",
  ["505"] = "HTTP Version Not Supported",
  ["506"] = "Variant Also Negotiates",
  ["507"] = "Insufficient Storage",
  ["508"] = "Loop Detected",
  ["510"] = "Not Extended",
  ["511"] = "Network Authentication Required",

  default = "Something is wrong"
}

local function make_response(error)
  local response = {}
  response.body = error.body
  response.headers = { ["Content-Type"] = error["content-type"] }
  return response
end

function _M.check_schema(conf, schema_type)
  if schema_type == core.schema.TYPE_METADATA then
    return core.schema.check(metadata_schema, conf)
  end

  return true
end

function _M.header_filter(_, ctx)
  local custom_response
  local metadata = apisix_plugin.plugin_metadata(plugin_name)
  if not metadata or not metadata.value.enable then
    return
  end

  -- Return custom error page only if upstream didn't respond
  if ngx.var.upstream_status then
    return
  end

  for key, value in pairs(metadata.value) do
    if not string.match(key, '^error_') then
      goto continue
    end


    local error_code = string.gsub(key, "error_", "")
    if ngx.status ~= tonumber(error_code) then
      goto continue
    end

    if value.body then
      custom_response = make_response(value)
      break
    end

    if value.redirect_url then
      ngx.status = ngx.HTTP_MOVED_TEMPORARILY -- 302
      ngx.header["Location"] = value.redirect_url
      return
    end

    ::continue::
  end

  -- This means a condition was triggered and we set a custom page
  if custom_response then
    -- header manipulation must be performed in header_filter phase
    if custom_response.headers then
      for key, value in pairs(custom_response.headers) do
        ngx.header[key] = value
      end
    end

    -- Parse NGiNX variables
    ctx.var.status_text = status_text[ngx.var.status] or status_text.default
    custom_response.body = apisix_utils.resolve_var(custom_response.body, ctx.var)

    -- Set Content-Length header before body_phase
    ngx.header['Content-Length'] = #(custom_response.body)
    if not metadata.value.set_content_length then
      ngx.header['Content-Length'] = nil
    end

    ctx.error_page_response_body = custom_response.body
  end
end

function _M.body_filter(conf, ctx)
  if ctx.error_page_response_body then
    local body = core.response.hold_body_chunk(ctx)

    -- Don't send a response until we've read all chunks
    if ngx.arg[2] == false and not body then
      return
    end

    -- Last chunk was read, so we can return the response
    ngx.arg[1] = ctx.error_page_response_body
    ctx.error_page_response_body = nil
  end
end

return _M
