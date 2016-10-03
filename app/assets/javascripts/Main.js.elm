module Main exposing (..)

import Map
import Models exposing (..)
import Navigation
import Routing
import Shared
import AppHome
import AppSearch
import AppFacilityDetails
import UserLocation
import Html exposing (Html)
import Html.App
import Utils exposing (mapFst, mapSnd)


type alias Flags =
    { fakeUserPosition : Bool
    , initialPosition : LatLng
    }


main : Program Flags
main =
    Navigation.programWithFlags Routing.parser
        { init = init
        , view = mainView
        , update = mainUpdate
        , subscriptions = subscriptions
        , urlUpdate = mainUrlUpdate
        }


type MainModel
    = -- pending map to be initialized from flag
      InitializingVR (Result String Route) LatLng Settings
      -- map initialized pending to determine which view/route to load
    | InitializedVR MapViewport Settings
    | HomeModel AppHome.Model Settings
    | FacilityDetailsModel AppFacilityDetails.Model Settings
    | SearchModel AppSearch.Model Settings


type MainMsg
    = MapViewportChangedVR MapViewport
    | Navigate Route
    | NavigateBack
    | HomeMsg AppHome.Msg
    | FacilityDetailsMsg AppFacilityDetails.Msg
    | SearchMsg AppSearch.Msg


init : Flags -> Result String Route -> ( MainModel, Cmd MainMsg )
init flags route =
    let
        settings =
            { fakeLocation =
                (if flags.fakeUserPosition then
                    Just flags.initialPosition
                 else
                    Nothing
                )
            }

        model =
            InitializingVR route flags.initialPosition settings

        cmds =
            [ Map.initializeMap flags.initialPosition ]
    in
        model ! cmds


subscriptions : MainModel -> Sub MainMsg
subscriptions model =
    case model of
        InitializingVR _ _ _ ->
            Map.mapViewportChanged MapViewportChangedVR

        InitializedVR _ _ ->
            Sub.none

        HomeModel model _ ->
            Sub.map HomeMsg <| AppHome.subscriptions model

        FacilityDetailsModel model settings ->
            AppFacilityDetails.subscriptions (hostAppFacilityDetails settings) model

        SearchModel model settings ->
            AppSearch.subscriptions (hostAppSearch settings) model


mainUpdate : MainMsg -> MainModel -> ( MainModel, Cmd MainMsg )
mainUpdate msg mainModel =
    case msg of
        Navigate route ->
            ( mainModel, Routing.navigate route )

        NavigateBack ->
            ( mainModel, Navigation.back 1 )

        _ ->
            case mainModel of
                InitializingVR route _ settings ->
                    case msg of
                        MapViewportChangedVR mapViewport ->
                            (InitializedVR mapViewport settings)
                                ! [ Routing.navigate (Routing.routeFromResult route) ]

                        _ ->
                            Debug.crash "map is not initialized yet"

                HomeModel model settings ->
                    case msg of
                        HomeMsg msg ->
                            case msg of
                                AppHome.FacilityClicked facilityId ->
                                    ( HomeModel model settings, navigateFacility facilityId )

                                AppHome.ServiceClicked serviceId ->
                                    ( HomeModel model settings, navigateSearchService serviceId )

                                AppHome.LocationClicked locationId ->
                                    ( HomeModel model settings, navigateSearchLocation locationId )

                                AppHome.Search q ->
                                    ( HomeModel model settings, navigateSearch q )

                                AppHome.Private _ ->
                                    wrapHome settings (AppHome.update settings msg model)

                        _ ->
                            Debug.crash "unexpected message"

                FacilityDetailsModel model settings ->
                    case msg of
                        FacilityDetailsMsg msg ->
                            AppFacilityDetails.update (hostAppFacilityDetails settings) msg model

                        _ ->
                            Debug.crash "unexpected message"

                SearchModel model settings ->
                    case msg of
                        SearchMsg msg ->
                            AppSearch.update (hostAppSearch settings) msg model

                        _ ->
                            Debug.crash "unexpected message"

                _ ->
                    ( mainModel, Cmd.none )


mainUrlUpdate : Result String Route -> MainModel -> ( MainModel, Cmd MainMsg )
mainUrlUpdate result mainModel =
    case mainModel of
        InitializingVR _ _ _ ->
            Debug.crash "urlUpdates should be handled after map is initialized"

        _ ->
            let
                viewport =
                    (mapViewport mainModel)

                settings =
                    (getSettings mainModel)

                userLocation =
                    (getUserLocation mainModel)
            in
                case Routing.routeFromResult result of
                    RootRoute ->
                        wrapHome settings (AppHome.init settings viewport userLocation)

                    FacilityRoute facilityId ->
                        AppFacilityDetails.init (hostAppFacilityDetails settings) viewport userLocation facilityId

                    SearchRoute searchSpec ->
                        AppSearch.init (hostAppSearch settings) searchSpec viewport userLocation

                    _ ->
                        Debug.crash "route not handled"


wrapHome : Settings -> ( AppHome.Model, Cmd AppHome.Msg ) -> ( MainModel, Cmd MainMsg )
wrapHome settings t =
    mapFst (\m -> HomeModel m settings) (mapSnd (Cmd.map HomeMsg) t)


mapViewport : MainModel -> MapViewport
mapViewport mainModel =
    case mainModel of
        InitializingVR _ _ _ ->
            Debug.crash "mapViewport should not be called before map is initialized"

        InitializedVR mapViewport _ ->
            mapViewport

        HomeModel model _ ->
            AppHome.mapViewport model

        FacilityDetailsModel model _ ->
            AppFacilityDetails.mapViewport model

        SearchModel model _ ->
            AppSearch.mapViewport model


getSettings : MainModel -> Settings
getSettings mainModel =
    case mainModel of
        InitializingVR _ _ settings ->
            settings

        InitializedVR mapViewport settings ->
            settings

        HomeModel model settings ->
            settings

        FacilityDetailsModel model settings ->
            settings

        SearchModel model settings ->
            settings


getUserLocation : MainModel -> UserLocation.Model
getUserLocation mainModel =
    case mainModel of
        HomeModel model _ ->
            AppHome.userLocation model

        FacilityDetailsModel model _ ->
            AppFacilityDetails.userLocation model

        SearchModel model _ ->
            AppSearch.userLocation model

        _ ->
            UserLocation.init


mainView : MainModel -> Html MainMsg
mainView mainModel =
    case mainModel of
        HomeModel model settings ->
            Shared.layout <| Html.App.map HomeMsg <| AppHome.view settings model

        FacilityDetailsModel model settings ->
            AppFacilityDetails.view (hostAppFacilityDetails settings) model

        SearchModel model settings ->
            AppSearch.view (hostAppSearch settings) model

        InitializingVR _ _ _ ->
            Shared.mapWithControl Nothing

        InitializedVR _ _ ->
            Shared.mapWithControl Nothing



--hostAppHome : Settings -> AppHome.Host MainModel MainMsg
--hostAppHome settings =
--    { model = \m -> HomeModel m settings
--    , msg = HomeMsg
--    , facilityClicked = Navigate << FacilityRoute
--    , serviceClicked = Navigate << (\id -> SearchRoute { q = Nothing, l = Nothing, latLng = Nothing, s = Just id })
--    , locationClicked = Navigate << (\id -> SearchRoute { q = Nothing, l = Just id, latLng = Nothing, s = Nothing })
--    , search = Navigate << (\q -> SearchRoute { q = Just q, l = Nothing, latLng = Nothing, s = Nothing })
--    , fakeLocation = settings.fakeLocation
--    }


navigateFacility : Int -> Cmd MainMsg
navigateFacility =
    Utils.performMessage << Navigate << FacilityRoute


navigateSearchService : Int -> Cmd MainMsg
navigateSearchService =
    Utils.performMessage << Navigate << (\id -> SearchRoute { q = Nothing, l = Nothing, latLng = Nothing, s = Just id })


navigateSearchLocation : Int -> Cmd MainMsg
navigateSearchLocation =
    Utils.performMessage << Navigate << (\id -> SearchRoute { q = Nothing, l = Just id, latLng = Nothing, s = Nothing })


navigateSearch : String -> Cmd MainMsg
navigateSearch =
    Utils.performMessage << Navigate << (\q -> SearchRoute { q = Just q, l = Nothing, latLng = Nothing, s = Nothing })


hostAppFacilityDetails : Settings -> AppFacilityDetails.Host MainModel MainMsg
hostAppFacilityDetails settings =
    { model = \m -> FacilityDetailsModel m settings
    , msg = FacilityDetailsMsg
    , navigateBack = NavigateBack
    }


hostAppSearch : Settings -> AppSearch.Host MainModel MainMsg
hostAppSearch settings =
    { model = \m -> SearchModel m settings
    , msg = SearchMsg
    , facilityClicked = Navigate << FacilityRoute
    , search = Navigate << SearchRoute
    , fakeLocation = settings.fakeLocation
    }



--andCmd : ( MainModel, Cmd MainMsg ) -> Cmd MainMsg -> ( MainModel, Cmd MainMsg )
--andCmd ( m, cmd1 ) cmd2 =
--    ( m, Cmd.batch [ cmd2, cmd1 ] )
