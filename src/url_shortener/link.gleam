import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/io
import gleam/json.{array, bool, int, null, object, string}
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import gleam/uri
import sqlight
import url_shortener/error.{type AppError}
import url_shortener/web.{json_response}
import wisp.{type Request, type Response}

type Link {
  Link(back_half: String, original_url: String, hits: Int, created: String)
}

pub fn shorten(req: Request, ctx) -> Response {
  let json =
    wisp.read_body_to_bitstring(req)
    |> result.unwrap(<<0>>)
    |> json.decode_bits(dynamic.dict(dynamic.string, dynamic.string))

  case json {
    Ok(data) -> handle_json(data, ctx)
    Error(err) -> error_json(err)
  }
}

pub fn info(req: Request, ctx) -> Response {
  json_response(501, False, string("Info endpoint is not yet implemented"))
}

fn handle_json(data: Dict(String, String), ctx) {
  case dict.get(data, "url") {
    Ok(url) -> validate_and_process_url(url, ctx)
    Error(_) -> json_response(400, False, string("URL not specified"))
  }
}

// fn name_handler(name: String, ctx: Context) {
//   let stmt = "INSERT INTO names (name) VALUES (?1) RETURNING id"
//   use rows <- result.then(
//     sqlight.query(
//       stmt,
//       on: ctx.db,
//       with: [sqlight.text(name)],
//       expecting: dynamic.element(0, dynamic.int),
//     )
//     |> result.map_error(fn(error) {
//       case error.code, error.message {
//         sqlight.ConstraintCheck, "CHECK constraint failed: empty_content" ->
//           error.ContentRequired
//         _, _ -> {
//           io.debug(error.message)
//           error.BadRequest
//         }
//       }
//     }),
//   )

//   let assert [id] = rows
//   io.debug(id)
//   Ok(id)
// }

pub fn random_back_half(length: Int) -> String {
  crypto.strong_random_bytes(length)
  |> bit_array.base64_url_encode(False)
  |> string.slice(0, length)
}

fn error_json(err) {
  case err {
    json.UnexpectedFormat([dynamic.DecodeError(e, f, _)]) ->
      json_response(
        400,
        False,
        string(
          "Invalid data type (expected "
          <> string.lowercase(e)
          <> ", found "
          <> string.lowercase(f)
          <> ")",
        ),
      )

    _ -> json_response(400, False, string("Invalid JSON"))
  }
}

fn validate_and_process_url(url, ctx) {
  case uri.parse(url) {
    Ok(uri.Uri(protocol, ..))
      if protocol == Some("http") || protocol == Some("https")
    -> {
      let link = insert_url(random_back_half(5), url, ctx)
      case link {
        Ok(Link(back_half, original_url, _, created)) ->
          json_response(
            code: 201,
            success: True,
            body: object([
              #("back_half", string(back_half)),
              #("original_url", string(original_url)),
              #("created", string(created)),
            ]),
          )
        Error(_) ->
          json_response(
            code: 500,
            success: False,
            body: string("An unexpected error occurred."),
          )
      }
    }
    _ -> {
      json_response(400, False, string("Invalid URL"))
    }
  }
}

fn link_decoder() -> dynamic.Decoder(Link) {
  dynamic.decode4(
    Link,
    dynamic.element(0, dynamic.string),
    dynamic.element(1, dynamic.string),
    dynamic.element(2, dynamic.int),
    dynamic.element(3, dynamic.string),
  )
}

fn insert_url(
  back_half,
  original_url,
  ctx: web.Context,
) -> Result(Link, AppError) {
  let stmt =
    "INSERT INTO links (back_half, original_url) 
    VALUES (?1, ?2) 
    RETURNING back_half, original_url, hits, created"
  use rows <- result.then(
    sqlight.query(
      stmt,
      on: ctx.db,
      with: [sqlight.text(back_half), sqlight.text(original_url)],
      expecting: link_decoder(),
    )
    |> result.map_error(fn(error) {
      case error.code, error.message {
        sqlight.ConstraintCheck, "CHECK constraint failed: empty_content" ->
          error.ContentRequired
        _, _ -> {
          io.print_error(error.message)
          error.BadRequest
        }
      }
    }),
  )

  let assert [link] = rows
  io.debug(link)
  Ok(link)
}
