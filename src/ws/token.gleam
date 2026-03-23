import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type TokenExtractionError {
  MissingToken
  InvalidAuthorizationHeader
}

pub fn from_request(
  request: Request(body),
) -> Result(String, TokenExtractionError) {
  from_parts(
    query_token: from_query(request) |> result_to_option,
    authorization_header: request.get_header(request, "authorization")
      |> result_to_option,
  )
}

pub fn from_parts(
  query_token query_token: Option(String),
  authorization_header authorization_header: Option(String),
) -> Result(String, TokenExtractionError) {
  case option_then(query_token, non_empty_option) {
    Some(token) -> Ok(token)
    None -> from_authorization_header_value(authorization_header)
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
  from_authorization_header_value(
    request.get_header(request, "authorization") |> result_to_option,
  )
}

pub fn from_authorization_header_value(
  authorization_header: Option(String),
) -> Result(String, TokenExtractionError) {
  let header = case authorization_header {
    Some(header) -> Ok(header)
    None -> Error(MissingToken)
  }

  use header <- result.try(header)
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

fn non_empty_option(value: String) -> Option(String) {
  non_empty(value) |> result_to_option
}

fn result_to_option(result: Result(a, e)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn option_then(value: Option(a), apply: fn(a) -> Option(b)) -> Option(b) {
  case value {
    Some(value) -> apply(value)
    None -> None
  }
}
