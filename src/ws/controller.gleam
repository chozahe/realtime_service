import dream/http/header
import dream/http/request.{type Request}
import dream/http/response.{type Response, json_response}
import dream/servers/mist/websocket
import gleam/result
import infra/auth.{authenticate as authenticate_token}
import ws/connection
import ws/handshake.{
  type HandshakeError, AuthenticationFailed, TokenExtractionFailed,
}
import ws/handshake_http
import ws/token

pub fn handle_upgrade(request: Request, _context, _services) -> Response {
  case authorize_request(request) {
    Ok(dependencies) ->
      websocket.upgrade_websocket(
        request,
        dependencies: dependencies,
        on_init: connection.on_init,
        on_message: connection.on_message,
        on_close: connection.on_close,
      )

    Error(error) -> unauthorized_response(error)
  }
}

fn authorize_request(
  request: Request,
) -> Result(connection.Dependencies, HandshakeError) {
  use access_token <- result.try(
    token.from_parts(
      query_token: request.get_query_param(request.query, "token"),
      authorization_header: header.get_header(request.headers, "authorization"),
    )
    |> result.map_error(TokenExtractionFailed),
  )

  authenticate_token(access_token)
  |> result.map(connection.Dependencies)
  |> result.map_error(AuthenticationFailed)
}

fn unauthorized_response(error: HandshakeError) -> Response {
  let response = handshake_http.unauthorized_response(error)
  json_response(response.status, response.body)
}
