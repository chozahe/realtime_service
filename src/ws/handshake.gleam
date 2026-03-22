import gleam/http/request.{type Request}
import gleam/result
import infra/auth.{authenticate as authenticate_token, type AuthenticatedAccessToken, type AuthError}
import ws/token.{from_request, type TokenExtractionError}

pub type HandshakeError {
  TokenExtractionFailed(TokenExtractionError)
  AuthenticationFailed(AuthError)
}

pub fn authenticate(request: Request(body)) -> Result(AuthenticatedAccessToken, HandshakeError) {
  use access_token <- result.try(
    from_request(request)
    |> result.map_error(TokenExtractionFailed),
  )

  authenticate_token(access_token)
  |> result.map_error(AuthenticationFailed)
}
