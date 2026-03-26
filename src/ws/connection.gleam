import contracts/ws/ws_error.{
  InvalidEnvelope, InvalidPayload, UnknownMessageType,
}
import contracts/ws/ws_inbound.{PingMessage, decode as decode_inbound}
import contracts/ws/ws_outbound.{
  type OutboundMessage, Connected, ErrorMessage, InvalidPayloadError, Pong,
  UnknownTypeError, encode as encode_outbound,
}
import dream/servers/mist/websocket
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import infra/auth.{type AuthenticatedAccessToken}
import tempo/datetime
import youid/uuid

pub type Dependencies {
  Dependencies(access_token: AuthenticatedAccessToken)
}

pub type ConnectionMessage {
  ExpireToken
}

pub type ConnectionState {
  ConnectionState(expiry_timer: process.Timer)
}

pub fn on_init(
  connection: websocket.Connection,
  dependencies: Dependencies,
) -> #(ConnectionState, Option(process.Selector(ConnectionMessage))) {
  let Dependencies(access_token) = dependencies
  let connection_id = "conn_" <> uuid.v7_string()
  let expiry_subject = process.new_subject()
  let expiry_timer =
    process.send_after(
      expiry_subject,
      milliseconds_until_expiry(access_token.expires_at),
      ExpireToken,
    )

  let state = ConnectionState(expiry_timer: expiry_timer)

  send_message(
    connection,
    connected_message(connection_id, access_token.user_id),
  )

  #(state, Some(process.new_selector() |> process.select(expiry_subject)))
}

pub fn on_message(
  state: ConnectionState,
  message: websocket.Message(ConnectionMessage),
  connection: websocket.Connection,
  _dependencies: Dependencies,
) -> websocket.Action(ConnectionState, ConnectionMessage) {
  case message {
    websocket.TextMessage(payload) ->
      handle_text_message(state, payload, connection)
    websocket.CustomMessage(ExpireToken) -> websocket.stop_connection()
    websocket.ConnectionClosed -> websocket.stop_connection()
    websocket.BinaryMessage(_) -> websocket.continue_connection(state)
  }
}

fn handle_text_message(
  state: ConnectionState,
  payload: String,
  connection: websocket.Connection,
) -> websocket.Action(ConnectionState, ConnectionMessage) {
  case decode_inbound(payload) {
    Ok(PingMessage(id:, ..)) -> {
      send_message(connection, Pong(id: id, server_time: current_time()))
      websocket.continue_connection(state)
    }

    Ok(_) -> websocket.continue_connection(state)

    Error(error) -> {
      send_message(connection, decode_error_to_outbound(error))
      websocket.continue_connection(state)
    }
  }
}

pub fn on_close(state: ConnectionState, _dependencies: Dependencies) -> Nil {
  let ConnectionState(expiry_timer:) = state
  let _ = process.cancel_timer(expiry_timer)
  Nil
}

fn send_message(
  connection: websocket.Connection,
  message: OutboundMessage,
) -> Nil {
  let _ =
    message
    |> encode_outbound
    |> websocket.send_text(connection, _)
    |> result.replace_error(Nil)

  Nil
}

fn connected_message(
  connection_id: String,
  user_id: uuid.Uuid,
) -> OutboundMessage {
  Connected(
    id: "ws_" <> uuid.v7_string(),
    connection_id: connection_id,
    user_id: user_id,
    server_time: current_time(),
  )
}

fn decode_error_to_outbound(error) -> OutboundMessage {
  case error {
    InvalidEnvelope(_) | InvalidPayload(..) ->
      ErrorMessage(
        id: "ws_" <> uuid.v7_string(),
        ref_id: None,
        code: InvalidPayloadError,
        message: "Invalid WebSocket message payload",
      )

    UnknownMessageType(_) ->
      ErrorMessage(
        id: "ws_" <> uuid.v7_string(),
        ref_id: None,
        code: UnknownTypeError,
        message: "Unknown WebSocket message type",
      )
  }
}

fn current_time() {
  timestamp.system_time()
  |> datetime.from_timestamp
}

fn milliseconds_until_expiry(expires_at: timestamp.Timestamp) -> Int {
  let now = timestamp.system_time()
  let diff =
    timestamp.difference(now, expires_at)
    |> duration.to_milliseconds

  case diff > 0 {
    True -> diff
    False -> 0
  }
}
