import dream/servers/mist/server
import ws/router

const default_port = 8082

pub fn main() -> Nil {
  server.new()
  |> server.router(router.create_router())
  |> server.listen(default_port)
}
