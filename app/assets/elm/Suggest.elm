module Suggest
    exposing
        ( Config
        , Model
        , Msg(..)
        , PrivateMsg
        , init
        , empty
        , update
        , subscriptions
        , hasContent
        , viewInput
        , viewInputWith
        , viewBody
        , mobileAdvancedSearch
        )

import AdvancedSearch
import Api
import Debounce
import Html exposing (..)
import Html.App
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import I18n exposing (..)
import List
import Models exposing (MapViewport, SearchSpec, FacilityType, Ownership, emptySearch, querySearch)
import Return
import Shared exposing (icon)
import String
import Utils exposing (perform)
import Svg
import Svg.Attributes


type alias Config =
    { mapViewport : MapViewport }


type alias Model =
    { query : String
    , advancedSearch : AdvancedSearch.Model
    , suggestions : Maybe (List Models.Suggestion)
    , d : Debounce.State
    , advanced : Bool
    }


type PrivateMsg
    = Input String
    | ApiSug Api.SuggestionsMsg
    | FetchSuggestions
    | Deb (Debounce.Msg Msg)
    | AdvancedSearchMsg AdvancedSearch.Msg


type Msg
    = FacilityClicked Int
    | ServiceClicked Int
    | LocationClicked Int
    | Search SearchSpec
    | Private PrivateMsg
    | UnhandledError String


hasContent : Model -> Bool
hasContent model =
    model.advanced || (model.query /= "") && (model.suggestions /= Nothing)


empty : Models.Settings -> ( Model, Cmd Msg )
empty settings =
    init settings emptySearch


init : Models.Settings -> SearchSpec -> ( Model, Cmd Msg )
init settings search =
    let
        ( advancedSearchModel, advancedSearchCmd ) =
            AdvancedSearch.init settings.facilityTypes settings.ownerships search
    in
        Return.singleton
            { query = Maybe.withDefault "" search.q
            , advancedSearch = advancedSearchModel
            , suggestions = Nothing
            , d = Debounce.init
            , advanced = False
            }
            |> Return.command (Cmd.map (Private << AdvancedSearchMsg) advancedSearchCmd)


clear : Model -> Model
clear model =
    { model
        | query = ""
        , suggestions = Nothing
        , d = Debounce.init
        , advanced = False
    }


searchSuggestions : Config -> Model -> ( Model, Cmd Msg )
searchSuggestions config model =
    ( { model | suggestions = Nothing }, Api.getSuggestions (Private << ApiSug) (Just config.mapViewport.center) model.query )


update : Config -> Msg -> Model -> ( Model, Cmd Msg )
update config msg model =
    case msg of
        Private msg ->
            case msg of
                Input query ->
                    if query == "" then
                        Return.singleton (clear model)
                    else
                        ( { model | query = query, suggestions = Nothing }, debCmd (Private FetchSuggestions) )

                FetchSuggestions ->
                    searchSuggestions config model

                ApiSug msg ->
                    case msg of
                        Api.SuggestionsSuccess query suggestions ->
                            if (query == model.query) then
                                ( { model | suggestions = Just suggestions }, Cmd.none )
                            else
                                -- ignore old requests
                                ( model, Cmd.none )

                        Api.SuggestionsFailed e ->
                            -- TODO
                            ( model, Cmd.none )

                Deb a ->
                    Debounce.update cfg a model

                AdvancedSearchMsg msg ->
                    case msg of
                        AdvancedSearch.Toggle ->
                            ( { model | advanced = not model.advanced }, Cmd.none )

                        AdvancedSearch.Perform search ->
                            Return.singleton model
                                |> perform (Search search)

                        AdvancedSearch.UnhandledError msg ->
                            Return.singleton model
                                |> perform (UnhandledError msg)

                        _ ->
                            AdvancedSearch.update model.advancedSearch msg
                                |> Return.mapBoth (Private << AdvancedSearchMsg) (setAdvancedSearch model)

        _ ->
            -- public events
            ( model, Cmd.none )


cfg : Debounce.Config Model Msg
cfg =
    Debounce.config .d (\model s -> { model | d = s }) (Private << Deb) 200


debCmd =
    Debounce.debounceCmd cfg


subscriptions : Sub Msg
subscriptions =
    Sub.map (Private << AdvancedSearchMsg) AdvancedSearch.subscriptions


viewInput : Model -> Html Msg
viewInput model =
    viewInputWith identity model (icon "search")


viewInputWith : (Msg -> a) -> Model -> Html a -> Html a
viewInputWith wmsg model trailing =
    let
        submitMsg =
            wmsg <| Search (querySearch model.query)

        inputMsg =
            wmsg << Private << Input

        actions =
            div [ class "actions" ]
                [ trailing
                , Html.App.map wmsg (advancedSearchIcon model)
                ]

        inputBar =
            if model.advanced then
                span [ class "advanced-search-title" ] [ text "Advanced search" ]
            else
                Html.form [ action "#", method "GET", autocomplete False, onSubmit submitMsg ]
                    [ input
                        [ type' "search"
                        , placeholder <| t SearchHealthFacility
                        , value model.query
                        , autofocus True
                        , onInput inputMsg
                        ]
                        []
                    ]
    in
        div [ class "search-box" ]
            [ div [ class "search" ]
                [ inputBar
                , actions
                ]
            ]


advancedSearchIcon : Model -> Html Msg
advancedSearchIcon model =
    a
        [ href "#"
        , Shared.onClick (Private (AdvancedSearchMsg AdvancedSearch.Toggle))
        , classList [ ( "active", not (AdvancedSearch.isEmpty model.advancedSearch) ) ]
        ]
        [ filterIcon model ]


filterIcon : Model -> Html a
filterIcon model =
    let
        class =
            (if AdvancedSearch.isEmpty model.advancedSearch then
                ""
             else
                "active"
            )
    in
        Svg.svg
            [ Svg.Attributes.class class
            , Svg.Attributes.viewBox "0 0 24 24"
            ]
            [ Svg.path [ Svg.Attributes.d "M22,4l-8,8v8H10V12L2,4Z" ] []
            ]


viewBody : Model -> List (Html Msg)
viewBody model =
    if model.advanced then
        Utils.mapHtml (Private << AdvancedSearchMsg) <|
            [ div [ class "hide-on-med-and-down" ] <|
                AdvancedSearch.embededView model.advancedSearch
            ]
    else
        case model.suggestions of
            Nothing ->
                []

            Just s ->
                [ suggestionsContent s ]


suggestionsContent : List Models.Suggestion -> Html Msg
suggestionsContent s =
    let
        entries =
            case s of
                [] ->
                    [ div
                        [ class "no-results" ]
                        [ span [ class "search-icon" ] [ icon "find_in_page" ]
                        , text "No results found"
                        ]
                    ]

                _ ->
                    List.map suggestion s
    in
        div [ class "content collection results" ] entries


suggestion : Models.Suggestion -> Html Msg
suggestion s =
    case s of
        Models.F { id, name, facilityType, adm } ->
            a
                [ class "collection-item avatar suggestion"
                , onClick <| FacilityClicked id
                ]
                [ icon "local_hospital"
                , span [ class "title" ] [ text name ]
                , p [ class "sub" ]
                    [ text (adm |> List.drop 1 |> List.reverse |> String.join ", ") ]
                ]

        Models.S { id, name, facilityCount } ->
            a
                [ class "collection-item avatar suggestion"
                , onClick <| ServiceClicked id
                ]
                [ icon "label"
                , span [ class "title" ] [ text name ]
                , p [ class "sub" ]
                    [ text <| t (FacilitiesCount { count = facilityCount }) ]
                ]

        Models.L { id, name, parentName } ->
            a
                [ class "collection-item avatar suggestion"
                , onClick <| LocationClicked id
                ]
                [ icon "location_on"
                , span [ class "title" ] [ text name ]
                , p [ class "sub" ]
                    [ text <| Maybe.withDefault "" parentName ]
                ]


mobileAdvancedSearch : Model -> List (Html Msg)
mobileAdvancedSearch model =
    Utils.mapHtml (Private << AdvancedSearchMsg) <|
        if model.advanced then
            [ div [ class "hide-on-large-only" ] <|
                AdvancedSearch.modalView model.advancedSearch
            ]
        else
            []


setAdvancedSearch : Model -> AdvancedSearch.Model -> Model
setAdvancedSearch model advancedSearch =
    { model | advancedSearch = advancedSearch }


isAdvancedSearchOpen : Model -> Bool
isAdvancedSearchOpen model =
    model.advanced
