module Decoders exposing (..)

import Date exposing (Date)
import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (decode, required, optional, hardcoded, nullable)
import Models exposing (..)
import Utils exposing (..)


search : Decoder SearchResult
search =
    object2 (\items nextUrl -> { items = items, nextUrl = nextUrl })
        ("items" := list facility)
        (maybe ("next_url" := string))


suggestions : Decoder (List Suggestion)
suggestions =
    decode (\f s l -> f ++ s ++ l)
        |> required "facilities" (list (map F facility))
        |> required "services" (list (map S service))
        |> required "locations" (list (map L location))


facility : Decoder Facility
facility =
    decode Facility
        |> required "id" int
        |> required "name" string
        |> required "position" latLng
        |> required "kind" string
        |> required "service_names" (list string)
        |> required "adm" (list string)
        |> required "contact_name" (nullable string)
        |> required "contact_phone" (nullable string)
        |> required "contact_email" (nullable string)
        |> required "report_to" (nullable string)
        |> required "last_updated" date


service : Decoder Service
service =
    decode Service
        |> required "id" int
        |> required "name" string
        |> required "facility_count" int


location : Decoder Location
location =
    decode Location
        |> required "id" int
        |> required "name" string
        |> required "parent_name" string


latLng : Decoder LatLng
latLng =
    decode (,)
        |> required "lat" float
        |> required "lng" float


date : Decoder Date
date =
    Json.Decode.map dateFromEpochSeconds float