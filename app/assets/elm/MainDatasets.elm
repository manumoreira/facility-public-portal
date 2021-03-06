port module MainDatasets exposing (Model, Msg, init, main, subscriptions, update, view)

import Dataset
    exposing
        ( Dataset
        , Event(..)
        , FileState
        , Fileset
        , FilesetTag(..)
        , ImportStartResult
        , empty
        , eventDecoder
        , fileLabel
        , fileMissing
        , humanReadableFileSize
        , humanReadableFileTimestamp
        , importDataset
        )
import Date exposing (Date)
import Dict exposing (Dict)
import Dom.Scroll exposing (toBottom)
import Html exposing (Html, a, button, div, h1, i, li, p, pre, span, text, ul)
import Html.App
import Html.Attributes exposing (attribute, class, download, href, id)
import Html.Events exposing (onClick)
import Http
import Json.Decode exposing (decodeValue, string)
import Process
import Spinner exposing (spinner)
import String
import Task
import Time exposing (Time)
import Utils


type alias Model =
    { dataset : Dataset
    , importState : Maybe ImportState
    , currentDate : Maybe Date
    , uploading : Dict String ()
    , currentTab : FilesetTag
    , downloadEndpoint : String
    }


type alias ImportDetails =
    { processId : String, log : List String }


type ImportState
    = Started ImportDetails
    | Succeeded ImportDetails
    | Failed ImportDetails


type alias ImportLog =
    { processId : String
    , log : String
    }


type ButtonAction
    = Action Msg
    | Navigate String


type Msg
    = DatasetEvent (Result String Dataset.Event)
    | ImportRaw
    | ImportOna
    | BackToFiles
    | ImportStarted (Result Http.Error ImportStartResult)
    | ImportSucceeded
    | ImportFailed
    | NoOp
    | DroppedFileEvent (Result String String)
    | CurrentTime Time
    | UploadingFile String
    | UploadedFile String
    | SelectTab FilesetTag


port datasetEvent : (Json.Decode.Value -> msg) -> Sub msg


port droppedFileEvent : (Json.Decode.Value -> msg) -> Sub msg


port uploadedFile : (String -> msg) -> Sub msg


port uploadingFile : (String -> msg) -> Sub msg


port requestFileUpload : String -> Cmd msg


port showModal : String -> Cmd msg


type alias Flags =
    String


main : Program Flags
main =
    Html.App.programWithFlags
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


init : Flags -> ( Model, Cmd Msg )
init downloadEndpoint =
    { dataset = Dataset.empty
    , importState = Nothing
    , currentDate = Nothing
    , uploading = Dict.empty
    , currentTab = Ona
    , downloadEndpoint = downloadEndpoint
    }
        ! [ Task.perform Utils.notFailing CurrentTime Time.now ]


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Dataset" ]
        , p []
            [ text "Drop your files here to update the dataset."
            , text " You could also import ONA files."
            , text " It's a good idea to download current files as a backup before running this process in case anything goes wrong."
            ]
        , div [ class "row" ]
            [ div [ class "col s12 pseudo-tabs" ]
                [ tab Ona model.currentTab "ONA"
                , tab Raw model.currentTab "RAW"
                ]
            ]
        , case model.importState of
            Nothing ->
                tabView model

            Just importState ->
                importView importState
        , div [ class "row card-panel" ]
            [ div [ class "col s10 import-flash" ]
                [ div [ class "valign-wrapper" ]
                    [ text <|
                        if missingFiles model then
                            "Upload all files in order to run an import."

                        else
                            ""
                    ]
                ]
            , div [ class "col s2" ]
                [ actionButton
                    (actionLabel model.importState)
                    (not <| missingFiles model)
                    (importAction model.currentTab model.importState)
                ]
            ]
        ]


actionLabel : Maybe ImportState -> Html Msg
actionLabel maybeState =
    case maybeState of
        Nothing ->
            text "Import"

        Just state ->
            case state of
                Started _ ->
                    spinner [ id "import-spinner" ] Spinner.White

                Succeeded _ ->
                    text "Map"

                Failed _ ->
                    text "Back"


importAction : FilesetTag -> Maybe ImportState -> ButtonAction
importAction fileset maybeState =
    case maybeState of
        Nothing ->
            case fileset of
                Ona ->
                    Action ImportOna

                Raw ->
                    Action ImportRaw

        Just state ->
            case state of
                Started _ ->
                    Action NoOp

                Succeeded _ ->
                    Navigate "/map"

                Failed _ ->
                    Action BackToFiles


actionButton : Html Msg -> Bool -> ButtonAction -> Html Msg
actionButton content enabled action =
    let
        baseAttributes =
            [ id "import-button"
            , class
                ("actions btn btn-large"
                    ++ (if enabled then
                            ""

                        else
                            " disabled"
                       )
                )
            ]
    in
    case action of
        Navigate uri ->
            a
                (href uri :: baseAttributes)
                [ content ]

        Action a ->
            button
                ((onClick <|
                    if enabled then
                        a

                    else
                        NoOp
                 )
                    :: baseAttributes
                )
                [ content ]


tab : FilesetTag -> FilesetTag -> String -> Html Msg
tab tab activeTab label =
    div
        [ class <| pseudoTabClass activeTab tab
        , onClick <| SelectTab tab
        ]
        [ text label ]


pseudoTabClass : FilesetTag -> FilesetTag -> String
pseudoTabClass activeTab evaldTab =
    if activeTab == evaldTab then
        "pseudo-tab active"

    else
        "pseudo-tab"


tabView : Model -> Html Msg
tabView model =
    filesetView model <| tabFileset model.dataset model.currentTab


tabFileset : Dataset -> FilesetTag -> Fileset
tabFileset model tab =
    case tab of
        Raw ->
            model.raw

        Ona ->
            model.ona


filesetView : Model -> Fileset -> Html Msg
filesetView model fileset =
    fileset
        |> Dict.toList
        |> List.map (configureFileView model)
        |> div [ class "row" ]


configureFileView : Model -> ( String, Maybe FileState ) -> Html Msg
configureFileView model ( filename, fileState ) =
    fileView model.downloadEndpoint model.currentDate ( filename, fileState ) (Dict.member filename model.uploading)


importDetails : ImportState -> ImportDetails
importDetails state =
    case state of
        Started details ->
            details

        Succeeded details ->
            details

        Failed details ->
            details


importFailed : ImportState -> Bool
importFailed state =
    case state of
        Failed _ ->
            True

        _ ->
            False


importView : ImportState -> Html msg
importView importState =
    pre [ id "import-log" ] (importState |> importDetails |> .log |> List.map text)


fileView : String -> Maybe Date -> ( String, Maybe FileState ) -> Bool -> Html Msg
fileView downloadEndpoint currentDate ( name, state ) isUploading =
    div [ class "col m4 s12" ]
        [ div [ class <| appliedClass "card-panel z-depth-0 file-card file-applied" state ]
            [ div [] [ text name ]
            , fileLineView <| fileLabel state "not yet uploaded" humanReadableFileSize
            , fileLineView <| fileLabel state "" (humanReadableFileTimestamp currentDate)
            , fileLineView <|
                if isUploading then
                    "Uploading..."

                else
                    ""
            , downloadButton downloadEndpoint name state
            ]
        ]


downloadButton : String -> String -> Maybe FileState -> Html Msg
downloadButton downloadEndpoint name mayF =
    case mayF of
        Nothing ->
            div [] []

        Just state ->
            if fileMissing state then
                div [] []

            else
                a
                    [ href <| downloadEndpoint ++ name
                    , download True
                    ]
                    [ i
                        [ class "material-icons file-download"
                        ]
                        [ text "arrow_downward" ]
                    ]


appliedClass : String -> Maybe FileState -> String
appliedClass baseClass state =
    case state of
        Nothing ->
            baseClass

        Just fileState ->
            if fileState.applied then
                String.concat [ baseClass, "file-applied" ]

            else
                baseClass


fileLineView : String -> Html msg
fileLineView line =
    div [ class "file-info" ] [ text line ]


missingFiles : Model -> Bool
missingFiles model =
    (model.currentTab == Ona && missingFilesForProcess model.dataset.ona)
        || (model.currentTab == Raw && missingFilesForProcess model.dataset.raw)


missingFilesForProcess : Fileset -> Bool
missingFilesForProcess set =
    set |> Dict.values |> List.any ((==) Nothing)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DatasetEvent result ->
            case result of
                Ok (DatasetUpdated dataset) ->
                    { model | dataset = dataset } ! []

                Ok (ImportLog log) ->
                    case model.importState of
                        Just importState ->
                            let
                                details =
                                    importDetails importState

                                newImportState =
                                    Just <| Started { details | log = details.log ++ [ log.log ] }
                            in
                            { model | importState = newImportState } ! [ scrollToBottom "import-log" ]

                        _ ->
                            model ! []

                Ok (ImportComplete result) ->
                    if result.exitCode == 0 then
                        model ! [ delayMessage 1000 ImportSucceeded ]

                    else
                        model ! [ delayMessage 1000 ImportFailed ]

                Err message ->
                    Debug.crash message

        ImportRaw ->
            model ! [ importDataset model.currentTab ImportStarted ]

        ImportOna ->
            model ! [ importDataset model.currentTab ImportStarted ]

        BackToFiles ->
            { model | importState = Nothing } ! []

        ImportStarted result ->
            case result of
                Ok result ->
                    { model | importState = Just <| Started { processId = result.processId, log = [] } }
                        ! []

                Err _ ->
                    model ! []

        ImportSucceeded ->
            (case model.importState of
                Nothing ->
                    model

                Just state ->
                    { model | importState = Just <| Succeeded <| importDetails state }
            )
                ! []

        ImportFailed ->
            (case model.importState of
                Nothing ->
                    model

                Just state ->
                    { model | importState = Just <| Failed <| importDetails state }
            )
                ! []

        NoOp ->
            model ! []

        DroppedFileEvent result ->
            case result of
                Ok filename ->
                    handleFileDrop model filename

                Err _ ->
                    model ! []

        CurrentTime now ->
            { model | currentDate = Just (Date.fromTime now) } ! []

        UploadingFile filename ->
            fileUploading model filename ! []

        UploadedFile filename ->
            fileUploaded model filename ! []

        SelectTab tab ->
            selectTab model tab ! []


selectTab : Model -> FilesetTag -> Model
selectTab model tab =
    { model | currentTab = tab }


fileUploading : Model -> String -> Model
fileUploading model filename =
    { model | uploading = Dict.insert filename () model.uploading }


fileUploaded : Model -> String -> Model
fileUploaded model filename =
    { model | uploading = Dict.remove filename model.uploading }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ datasetEvent (decodeValue Dataset.eventDecoder >> DatasetEvent)
        , droppedFileEvent (decodeValue string >> DroppedFileEvent)
        , Time.every Time.minute CurrentTime
        , uploadingFile UploadingFile
        , uploadedFile UploadedFile
        ]


delayMessage : Float -> msg -> Cmd msg
delayMessage delay msg =
    let
        handler =
            always msg
    in
    Process.sleep delay
        |> Task.perform handler handler


scrollToBottom : String -> Cmd Msg
scrollToBottom nodeId =
    let
        handler =
            always NoOp
    in
    toBottom nodeId
        |> Task.perform handler handler


handleFileDrop : Model -> String -> ( Model, Cmd msg )
handleFileDrop model filename =
    if Dataset.knownFile filename model.dataset then
        if not (Dataset.inFileset filename model.dataset.ona) && model.currentTab == Ona then
            selectTab model Raw ! [ requestFileUpload filename ]

        else if not (Dataset.inFileset filename model.dataset.raw) && model.currentTab == Raw then
            selectTab model Ona ! [ requestFileUpload filename ]

        else
            model ! [ requestFileUpload filename ]

    else
        model
            ! [ showModal <|
                    """
Unknown file.

Check that the file you're dropping is listed in either tab ONA or tab Raw.

If it's not, determine which file you want to replace, and if the contents are right, """
                        ++ """rename the file so that it matches the list and try dropping again."""
              ]
