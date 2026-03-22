import gleam/http/request.{type Request}
import gleam/list
import gleam/result
import gleam/string

pub type TokenExtractionError {
  MissingToken
  InvalidAuthorizationHeader
}

pub fn from_request(request: Request(body)) -> Result(String, TokenExtractionError) {
  case from_query(request) {
    Ok(token) -> Ok(token)
    Error(Nil) -> from_authorization_header(request)
  }
}

pub fn from_query(request: Request(body)) -> Result(String, Nil) {
  use query <- result.try(request.get_query(request))
  use token <- result.try(list.key_find(query, "token"))
  non_empty(token)
}

pub fn from_authorization_header(
  request: Request(body),
) -> Result(String, TokenExtractionError) {
  use header <- result.try(
    request.get_header(request, "authorization")
    |> result.replace_error(MissingToken),
  )

  case header {
    "Bearer " <> token -> parse_bearer_token(token)
    "bearer " <> token -> parse_bearer_token(token)
    _ -> Error(InvalidAuthorizationHeader)
  }
}

fn parse_bearer_token(token: String) -> Result(String, TokenExtractionError) {
  token
  |> string.trim
  |> non_empty
  |> result.replace_error(InvalidAuthorizationHeader)
}

fn non_empty(value: String) -> Result(String, Nil) {
  case string.trim(value) {
    "" -> Error(Nil)
    trimmed -> Ok(trimmed)
  }
}
