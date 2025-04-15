<div align="center">

[![APISIX][apisix-shield]][apisix-url]
[![NGINX][nginx-shield]][nginx-url]
[![Lua][lua-shield]][lua-url]
[![Perl][perl-shield]][perl-url]
[![YAML][yaml-shield]][yaml-url]\
[![Build Status][build-status-shield]][build-status-url]

# APISIX Plugin error-page-advanced

This custom plugin allows APISIX to return a custom error page for each code. It allows extra customizations than [error-page](https://github.com/mikyll/apisix-plugin-error-page), such as any status code or request redirection.

</div>

## Table of Contents

- [APISIX Plugin error-page-advanced](#apisix-plugin-error-page-advanced)
  - [Table of Contents](#table-of-contents)
  - [Plugin Usage](#plugin-usage)
    - [Installation](#installation)
    - [Configuration](#configuration)
      - [Plugin Metadata](#plugin-metadata)
    - [Enable Plugin](#enable-plugin)
      - [Traditional](#traditional)
      - [Standalone](#standalone)
    - [Example Usage](#example-usage)
  - [Examples](#examples)
    - [Standalone Example](#standalone-example)
      - [Setup](#setup)
      - [Test Routes](#test-routes)
  - [Learn More](#learn-more)

## Plugin Usage

### Installation

To install custom plugins in APISIX there are 2 methods:

- placing them alongside other built-in plugins, in `${APISIX_INSTALL_DIRECTORY}/apisix/plugins/` (by default `/usr/local/apisix/apisix/plugins/`);
- placing them in a custom directory and setting `apisix.extra_lua_path` to point that directory, in `config.yaml`.

[Back to TOC](#table-of-contents)

### Configuration

This plugin can be configured for [Routes](https://apisix.apache.org/docs/apisix/terminology/route/) or [Global Rules](https://apisix.apache.org/docs/apisix/terminology/global-rule/).

#### Plugin Metadata

| Name                   | Type    | Required | Default | Valid values | Description                                                                                                                                                                                                               |
| ---------------------- | ------- | -------- | ------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| enable                 | boolean | False    | `false` |              | If true, enable the plugin.                                                                                                                                                                                               |
| set_content_length     | boolean | False    | `true`  |              | If true automatically set the Content-Length header. If set to false, removes the header.                                                                                                                                 |
| error_XXX              | object  | False    |         |              | Error page to return when APISIX returns XXX status codes.                                                                                                                                                                |
| error_XXX.body         | string  | False    |         |              | Response body. This can contain [NGiNX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html#variables). An extra variable `$status_text` is also available, which contains the message of the status code. |
| error_XXX.content-type | string  | False    |         |              | Response content type.                                                                                                                                                                                                    |
| error_XXX.redirect_url | string  | False    |         |              | URL to redirect the request to.                                                                                                                                                                                           |

> [!IMPORTANT]
> Plugin metadata set global values, shared accross all plugin instances. For example, if we have 2 different routes with `error-page-advanced` plugin enabled, `plugin_metadata` values will be the same for both of them.

### Enable Plugin

The examples below enable `error-page-advanced` plugin globally. With these configurations, APISIX will return a custom error message for status codes `404` and `504`, on every route (even on undefined ones).

#### Traditional

Configure the plugin metadata:

```bash
curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/error-page-advanced  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "enable": true,
  "error_404": {
    "body": "{\"status_code\":$status,\"error\":\"$status_text\"}",
    "content-type": "application/json"
  },
  "error_504": {
    "redirect_url": "https://httpbin.org/get?foo=bar"
  },
}'
```

Enable the plugin globally, using global rules:

```bash
curl http://127.0.0.1:9180/apisix/admin/global_rules/error-page-advanced  -H "X-API-KEY: $admin_key" -X PUT -d '
{
  "plugins": {
    "error-page-advanced": {}
  }
}'
```

#### Standalone

Configure the plugin metadata:

```yaml
plugin_metadata:
  - id: error-page-advanced
    enable: true
    error_404:
      body: |
        {
          "status_code": $status,
          "error": "$status_text"
        }
      content-type: "application/json"
    error_504:
      redirect_url: "https://httpbin.org/get?foo=bar"
```

Enable the plugin globally, using global rules:

```yaml
global_rules:
  - id: generic_error_page_advanced
    plugins:
      error-page-advanced: {}
```

### Example Usage

Send some request to test error pages:

- Route not defined (overrides default error page for 404):

  ```bash
  curl -iL "localhost:9080/unknown"
  ```

  Response:

  ```bash
  HTTP/1.1 404 Not Found
  Content-Type: application/json
  Connection: keep-alive
  Server: APISIX/3.12.0
  Content-Length: 49

  {
    "status_code": 404,
    "error": "Not Found"
  }
  ```

- Status code 504 returned from APISIX:
  
  ```bash
  curl -iL "localhost:9080/apisix_status/504"
  ```

  Response:

  ```bash
  HTTP/1.1 302 Moved Temporarily
  Content-Type: text/html
  Content-Length: 239
  Connection: keep-alive
  Server: APISIX/3.11.0
  Location: https://httpbin.org/get?foo=bar

  HTTP/2 200 
  content-type: application/json
  content-length: 283
  server: gunicorn/19.9.0
  access-control-allow-origin: *
  access-control-allow-credentials: true

  {
    "args": {
      "foo": "bar"
    }, 
    "headers": {
      "Accept": "*/*", 
      "Host": "httpbin.org", 
      "User-Agent": "curl/8.5.0", 
      "X-Amzn-Trace-Id": "Root=1-67fe8ffb-0368d480171b6ed602af7956"
    }, 
    "origin": "X.X.X.X", 
    "url": "https://httpbin.org/get?foo=bar"
  }
  ```

[Back to TOC](#table-of-contents)

## Examples

Folder [`examples/`](examples/) contains a simple example that shows how to setup APISIX locally on Docker, and load `error-page-advanced` plugin.

For more example ideas, have a look at [github.com/mikyll/apisix-examples](https://github.com/mikyll/apisix-examples).

[Back to TOC](#table-of-contents)

### Standalone Example

#### Setup

See [`apisix.yaml`](examples/apisix-docker-standalone/conf/apisix.yaml).

Run the following command to setup the example:

```bash
docker compose -f examples/apisix-docker-standalone/compose.yaml up
```

#### Test Routes

Run [`test_routes.sh`](examples/utils/test_routes.sh) to send testing requests.

[Back to TOC](#table-of-contents)

## Learn More

- [APISIX Source Code](https://github.com/apache/apisix)
- [APISIX Deployment Modes](https://apisix.apache.org/docs/apisix/deployment-modes/)
- [Developing custom APISIX plugins](https://apisix.apache.org/docs/apisix/plugin-develop)
- [APISIX testing framework](https://apisix.apache.org/docs/apisix/internal/testing-framework)
- [APISIX debug mode](https://apisix.apache.org/docs/apisix/debug-mode/)
- [NGiNX variables](https://nginx.org/en/docs/http/ngx_http_core_module.html#variables)
- [APISIX Examples](https://github.com/mikyll/apisix-examples)

<!-- GitHub Shields -->

[apisix-shield]: https://custom-icon-badges.demolab.com/badge/APISIX-grey.svg?logo=apisix_logo
[apisix-url]: https://apisix.apache.org/
[nginx-shield]: https://img.shields.io/badge/Nginx-%23009639.svg?logo=nginx
[nginx-url]: https://nginx.org/en/
[lua-shield]: https://img.shields.io/badge/Lua-%232C2D72.svg?logo=lua&logoColor=white
[lua-url]: https://www.lua.org/
[perl-shield]: https://img.shields.io/badge/Perl-%2339457E.svg?logo=perl&logoColor=white
[perl-url]: https://www.perl.org/
[yaml-shield]: https://img.shields.io/badge/YAML-%23ffffff.svg?logo=yaml&logoColor=151515
[yaml-url]: https://yaml.org/
[build-status-shield]: https://github.com/mikyll/apisix-plugin-error-page-advanced/actions/workflows/ci.yml/badge.svg
[build-status-url]: https://github.com/mikyll/apisix-plugin-error-page-advanced/actions