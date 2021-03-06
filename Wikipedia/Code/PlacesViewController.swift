import UIKit
import WMF
import TUSafariActivity
#if OSM
import Mapbox
#endif

import MapKit

@objc(WMFPlacesViewController)
class PlacesViewController: PreviewingViewController, UISearchBarDelegate, ArticlePopoverViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, PlaceSearchSuggestionControllerDelegate, WMFLocationManagerDelegate, NSFetchedResultsControllerDelegate, UIPopoverPresentationControllerDelegate, EnableLocationViewControllerDelegate, ArticlePlaceViewDelegate, AnalyticsViewNameProviding, UIGestureRecognizerDelegate, TouchOutsideOverlayDelegate, PlaceSearchFilterListDelegate {

    fileprivate var mapView: MapView!
    
    @IBOutlet weak var mapContainerView: UIView!
    
    @IBOutlet weak var redoSearchButton: UIButton!
    @IBOutlet weak var didYouMeanButton: UIButton!
    @IBOutlet weak var extendedNavBarView: UIView!
    @IBOutlet weak var extendedNavBarViewHeightContraint: NSLayoutConstraint!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var recenterOnUserLocationButton: UIButton!
    @IBOutlet weak var titleViewSearchBar: UISearchBar!
    @IBOutlet weak var mapListToggle: UISegmentedControl!
    @IBOutlet weak var filterSelectorView: PlaceSearchFilterSelectorView!
    @IBOutlet weak var filterDropDownContainerView: UIView!
    @IBOutlet weak var filterDropDownTableView: UITableView!
    @IBOutlet weak var closeSearchButton: UIButton!
    @IBOutlet weak var searchBarToMapListToggleTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var searchBarToCloseTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlayContainerView: RoundedCornerView!
    @IBOutlet weak var listAndSearchOverlayFilterSelectorContainerView: UIView!
    @IBOutlet weak var listAndSearchOverlaySearchContainerView: UIView!
    @IBOutlet weak var listAndSearchOverlaySearchBar: UISearchBar!
    @IBOutlet weak var listAndSearchOverlayBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlayHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlayFilterSelectorContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySearchHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySliderHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySearchCancelButtonHideConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySearchCancelButtonShowConstraint: NSLayoutConstraint!
    @IBOutlet weak var listAndSearchOverlaySliderView: UIView!
    @IBOutlet weak var listView: UITableView!
    @IBOutlet weak var searchSuggestionView: UITableView!
    @IBOutlet weak var emptySearchOverlayView: PlaceSearchEmptySearchOverlayView!
    
    public var dataStore: MWKDataStore!

    fileprivate let locationSearchFetcher = WMFLocationSearchFetcher()
    fileprivate let searchFetcher = WMFSearchFetcher()
    fileprivate let wikidataFetcher = WikidataFetcher()
    fileprivate let locationManager = WMFLocationManager.fine()
    fileprivate let animationDuration = 0.6
    fileprivate let animationScale = CGFloat(0.6)
    fileprivate let popoverFadeDuration = 0.25
    fileprivate let searchHistoryCountLimit = 15
    fileprivate var searchSuggestionController: PlaceSearchSuggestionController!
    fileprivate var searchBar: UISearchBar? {
        didSet {
            oldValue?.delegate = nil
            searchBar?.text = oldValue?.text
            searchBar?.delegate = self
        }
    }
    
    fileprivate var siteURL: URL {
        return MWKLanguageLinkController.sharedInstance().appLanguage?.siteURL() ?? NSURL.wmf_URLWithDefaultSiteAndCurrentLocale()!
    }
    
    fileprivate var currentGroupingPrecision: QuadKeyPrecision = 1
    fileprivate var selectedArticlePopover: ArticlePopoverViewController?
    fileprivate var selectedArticleAnnotationView: MapAnnotationView?
    fileprivate var selectedArticleKey: String?
    fileprivate var articleKeyToSelect: String?
    fileprivate var currentSearchRegion: MKCoordinateRegion?
    fileprivate var performDefaultSearchOnNextMapRegionUpdate = false
    fileprivate var isMovingToRegion = false

    fileprivate var previouslySelectedArticlePlaceIdentifier: Int?
    fileprivate var didYouMeanSearch: PlaceSearch?
    fileprivate var searching: Bool = false
    fileprivate let tracker = PiwikTracker.sharedInstance()
    fileprivate let mapTrackerContext: AnalyticsContext = "Places_map"
    fileprivate let listTrackerContext: AnalyticsContext = "Places_list"
    fileprivate let searchTrackerContext: AnalyticsContext = "Places_search"
    fileprivate let imageController = ImageController.shared
    fileprivate var searchFilterListController: PlaceSearchFilterListController!
    fileprivate var extendedNavBarHeightOrig: CGFloat?
    fileprivate var touchOutsideOverlayView: TouchOutsideOverlayView!
    fileprivate var _displayCountForTopPlaces: Int?
    fileprivate var displayCountForTopPlaces: Int {
        get {
            switch (self.currentSearchFilter) {
            case .top:
                return articleFetchedResultsController.fetchedObjects?.count ?? 0
            case .saved:
                return _displayCountForTopPlaces ?? 0
            }
        }
    }
    
    lazy fileprivate var placeSearchService: PlaceSearchService! = {
        return PlaceSearchService(dataStore: self.dataStore)
    }()
    
    // MARK: - View Lifecycle
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        title = WMFLocalizedString("places-title", value: "Places", comment: "Title of the Places screen shown on the places tab.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let mapViewFrame = mapContainerView.bounds
        #if OSM
            let styleURL = Bundle.main.url(forResource: "mapstyle", withExtension: "json")
            mapView = MapView(frame: mapViewFrame, styleURL: styleURL)
            mapView.delegate = self
            mapView.allowsRotating = false
            mapView.allowsTilting = false
            mapView.showsUserLocation = false
            mapView.logoView.isHidden = true
        #else
            mapView = MapView(frame: mapViewFrame)
            mapView.delegate = self
            // Setup map view
            mapView.mapType = .standard
            mapView.showsBuildings = false
            mapView.showsTraffic = false
            mapView.showsPointsOfInterest = false
            mapView.showsScale = false
            mapView.showsUserLocation = true
            mapView.isRotateEnabled = false
            mapView.isPitchEnabled = false
        #endif
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapContainerView.addSubview(mapView)

        
        view.tintColor = .wmf_blue
        
        wmf_addBottomShadow(view: extendedNavBarView)
        extendedNavBarHeightOrig = extendedNavBarViewHeightContraint.constant
        
        searchFilterListController = PlaceSearchFilterListController(delegate: self)
        searchFilterListController.tableView = filterDropDownTableView
        filterDropDownTableView.dataSource = searchFilterListController
        filterDropDownTableView.delegate = searchFilterListController
        
        touchOutsideOverlayView = TouchOutsideOverlayView(frame: self.view.bounds)
        touchOutsideOverlayView.delegate = self

        // config filter drop down
        wmf_addBottomShadow(view: filterDropDownContainerView)

        navigationController?.setNavigationBarHidden(false, animated: true)

        // Setup location manager
        locationManager.delegate = self
    
        // Setup Redo search button
        redoSearchButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        redoSearchButton.backgroundColor = view.tintColor
        redoSearchButton.setTitleColor(.white, for: .normal)
        redoSearchButton.setTitle(WMFLocalizedString("places-search-this-area", value:"Results in this area", comment:"A button title that indicates the search will be redone in the visible area"), for: .normal)
        redoSearchButton.isHidden = true
        
        // Setup Did You Mean button
        didYouMeanButton.backgroundColor = view.tintColor
        didYouMeanButton.setTitleColor(.white, for: .normal)
        didYouMeanButton.isHidden = true
        didYouMeanButton.titleLabel?.adjustsFontSizeToFitWidth = true
        didYouMeanButton.titleLabel?.textAlignment = .center
        
        // Setup map/list toggle
        let map = #imageLiteral(resourceName: "places-map")
        let list = #imageLiteral(resourceName: "places-list")
        map.accessibilityLabel = WMFLocalizedString("places-accessibility-show-as-map", value:"Show as map", comment:"Accessibility label for the show as map toggle item")
        list.accessibilityLabel = WMFLocalizedString("places-accessibility-show-as-list", value:"Show as list", comment:"Accessibility label for the show as list toggle item")
        mapListToggle.setImage(map, forSegmentAt: 0)
        mapListToggle.setImage(list, forSegmentAt: 1)
        mapListToggle.selectedSegmentIndex = 0
        mapListToggle.addTarget(self, action: #selector(updateViewModeFromSegmentedControl), for: .valueChanged)
        mapListToggle.tintColor = .wmf_blue
        
        // Setup close search button
        closeSearchButton.accessibilityLabel = WMFLocalizedString("places-accessibility-close-search", value:"Close search", comment:"Accessibility label for the button to close search")
        
        // Setup recenter button
        recenterOnUserLocationButton.accessibilityLabel = WMFLocalizedString("places-accessibility-recenter-map-on-user-location", value:"Recenter on your location", comment:"Accessibility label for the recenter map on the user's location button")
        recenterOnUserLocationButton.imageEdgeInsets = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 1)

        listAndSearchOverlayContainerView.corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        listAndSearchOverlayContainerView.radius = 5
        
        // Setup list view
        listView.dataSource = self
        listView.delegate = self
        listView.register(WMFNearbyArticleTableViewCell.wmf_classNib(), forCellReuseIdentifier: WMFNearbyArticleTableViewCell.identifier())
        listView.estimatedRowHeight = WMFNearbyArticleTableViewCell.estimatedRowHeight()
        
        // Setup search suggestions
        searchSuggestionController = PlaceSearchSuggestionController()
        searchSuggestionController.tableView = searchSuggestionView
        searchSuggestionController.delegate = self

        // Setup search bar
        titleViewSearchBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        titleViewSearchBar.returnKeyType = .search
        titleViewSearchBar.searchBarStyle = .minimal
        titleViewSearchBar.placeholder = WMFLocalizedString("places-search-default-text", value:"Search Places", comment:"Placeholder text that displays where is there no current place search\n{{Identical|Search}}")
        
        listAndSearchOverlaySearchBar.returnKeyType = titleViewSearchBar.returnKeyType
        listAndSearchOverlaySearchBar.searchBarStyle = titleViewSearchBar.searchBarStyle
        listAndSearchOverlaySearchBar.placeholder = WMFLocalizedString("places-search-default-text", value:"Search", comment:"Placeholder text that displays where is there no current place search\n{{Identical|Search}}")
        
        if UIAccessibilityIsVoiceOverRunning() {
            viewMode = .list
        } else {
            viewMode = .map
        }

        self.view.layoutIfNeeded()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        // Update saved places locations
        placeSearchService.fetchSavedArticles(searchString: nil)
        
        if let isSearchBarInNavigationBar = self.isSearchBarInNavigationBar {
            wmf_updateNavigationBar(removeUnderline: isSearchBarInNavigationBar)
        } else {
            DDLogDebug("not updating navigation bar because search bar isn't set yet")
        }
        
        super.viewWillAppear(animated)
        
        let defaults = UserDefaults.wmf_userDefaults()
        if !defaults.wmf_placesHasAppeared() {
            defaults.wmf_setPlacesHasAppeared(true)
        }
        
        if isViewModeOverlay {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }

        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        guard WMFLocationManager.isAuthorized() else {
            if !defaults.wmf_placesDidPromptForLocationAuthorization() {
                defaults.wmf_setPlacesDidPromptForLocationAuthorization(true)
                promptForLocationAccess()
            } else {
                performDefaultSearchOnNextMapRegionUpdate = currentSearch == nil
            }
            return
        }
        
        locationManager.startMonitoringLocation()
        mapView.showsUserLocation = true
        
        tracker?.wmf_logView(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        wmf_updateNavigationBar(removeUnderline: false)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        locationManager.stopMonitoringLocation()
        mapView.showsUserLocation = false
    }
    
    func selectVisibleArticle(articleKey: String) -> Bool {
        let annotations = mapView.visibleAnnotations
        for annotation in annotations {
            guard let place = annotation as? ArticlePlace,
                place.articles.count == 1,
                let article = place.articles.first,
                article.key == articleKey else {
                    continue
            }
            selectArticlePlace(place)
            return true
        }
        return false
    }

    func selectVisibleKeyToSelectIfNecessary() {
        guard !isMovingToRegion, countOfAnimatingAnnotations == 0, let keyToSelect = articleKeyToSelect, viewMode == .map else {
            return
        }
        guard selectVisibleArticle(articleKey: keyToSelect) else {
            return
        }
        articleKeyToSelect = nil

    }

    
    func updateShouldShowAllImagesIfNecessary() {
        let visibleAnnotations = mapView.visibleAnnotations
        var visibleArticleCount = 0
        var visibleGroupCount = 0
        for annotation in visibleAnnotations {
            guard let place = annotation as? ArticlePlace else {
                continue
            }
            if place.articles.count == 1 {
                visibleArticleCount += 1
            } else {
                visibleGroupCount += 1
            }
        }
        let articlesPerSquarePixel = CGFloat(visibleArticleCount) / mapView.bounds.width * mapView.bounds.height
        let shouldShowAllImages = visibleGroupCount == 0 && visibleArticleCount > 0 && articlesPerSquarePixel < 40
        set(shouldShowAllImages: shouldShowAllImages)
    }
    
    func set(shouldShowAllImages: Bool) {
        if shouldShowAllImages != showingAllImages {
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) as? ArticlePlaceView else {
                    continue
                }
                view.set(alwaysShowImage: shouldShowAllImages, animated: true)
            }
            showingAllImages = shouldShowAllImages
        }
    }
    
    var countOfAnimatingAnnotations = 0 {
        didSet {
            if countOfAnimatingAnnotations == 0 {
                selectVisibleKeyToSelectIfNecessary()
            }
        }
    }
    
    // MARK: - Keyboard
    
    func keyboardChanged(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
            let frameValue = userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue else {
                return
        }
        let keyboardScreenFrame = frameValue.cgRectValue
        var inset = searchSuggestionView.contentInset
        inset.bottom = keyboardScreenFrame.size.height
        searchSuggestionView.contentInset = inset
        
        let keyboardViewFrame = emptySearchOverlayView.convert(keyboardScreenFrame, from: (UIApplication.shared.delegate?.window)!)
        
        switch (notification.name) {
        case NSNotification.Name.UIKeyboardWillShow:
            let overlap = keyboardViewFrame.intersection(emptySearchOverlayView.frame)
            var newFrame = emptySearchOverlayView.frame
            newFrame.size.height -= overlap.height
            emptySearchOverlayView.frame = newFrame
            
        case NSNotification.Name.UIKeyboardWillHide:
            // reset the frame
            emptySearchOverlayView.frame = searchSuggestionView.frame
            
        default:
            DDLogWarn("unexpected notification \(notification.name)")
        }

        self.view.setNeedsLayout()
    }
    
    // MARK: - Map Region
    
    fileprivate func region(thatFits regionToFit: MKCoordinateRegion) -> MKCoordinateRegion {
        var region = mapView.regionThatFits(regionToFit)
        
        if region.span.latitudeDelta == 0 || region.span.longitudeDelta == 0 ||
           region.span.latitudeDelta.isNaN || region.span.longitudeDelta.isNaN ||
           region.span.latitudeDelta.isInfinite || region.span.longitudeDelta.isInfinite {
            region = regionToFit
        }

        return region
    }
    
    fileprivate var _mapRegion: MKCoordinateRegion?
    
    fileprivate var mapRegion: MKCoordinateRegion? {
        set {
            guard let value = newValue else {
                _mapRegion = nil
                return
            }
            
            let region = self.region(thatFits: value)
            _mapRegion = region
            
            regroupArticlesIfNecessary(forVisibleRegion: region)
            updateViewIfMapMovedSignificantly(forVisibleRegion: region)
            
            let mapViewRegion = mapView.region
            guard mapViewRegion.center.longitude != region.center.longitude || mapViewRegion.center.latitude != region.center.latitude || mapViewRegion.span.longitudeDelta != region.span.longitudeDelta || mapViewRegion.span.latitudeDelta != region.span.latitudeDelta else {
                selectVisibleKeyToSelectIfNecessary()
                return
            }
            
            guard !isViewModeOverlay || overlayState == .min else {
                let factor = UIApplication.shared.wmf_isRTL ? 0.1 : -0.1
                let adjustedCenter = CLLocationCoordinate2DMake(region.center.latitude, region.center.longitude + factor * region.span.latitudeDelta)
                let adjustedRegion = MKCoordinateRegionMake(adjustedCenter, region.span)
                mapView.setRegion(adjustedRegion, animated: true)
                return
            }

            mapView.setRegion(region, animated: true)
        }
        
        get {
            return _mapRegion
        }
    }
    
    func region(thatFits articles: [WMFArticle]) -> MKCoordinateRegion {
        let coordinates: [CLLocationCoordinate2D] =  articles.flatMap({ (article) -> CLLocationCoordinate2D? in
            return article.coordinate
        })
        guard coordinates.count > 1 else {
            return coordinates.wmf_boundingRegion(with: 10000)
        }
        
        let initialRegion = coordinates.wmf_boundingRegion(with: 50)
        return coordinates.wmf_boundingRegion(with: 0.25 * initialRegion.width)
    }
    
    // MARK: - Searching
    
    var currentSearch: PlaceSearch? {
        didSet {
            guard let search = currentSearch else {
                return
            }
            
            updateSearchFilterTitle()
            updateSearchBarText(forSearch: search)

            performSearch(search)
            
            switch search.type {
            case .nearby:
                break
            case .location:
                guard !search.needsWikidataQuery else {
                    break
                }
                fallthrough
            default:
                saveToHistory(search: search)
            }
        }
    }
    
    func performDefaultSearchIfNecessary(withRegion region: MKCoordinateRegion?) {
        guard currentSearch == nil else {
            return
        }
        performDefaultSearch(withRegion: region)
    }
    
    func isDefaultSearch(_ placeSearch: PlaceSearch) -> Bool {
        return placeSearch.type == .location && placeSearch.string == nil && placeSearch.searchResult == nil && placeSearch.origin == .system
    }
    
    func performDefaultSearch(withRegion region: MKCoordinateRegion?) {
        currentSearch = PlaceSearch(filter: currentSearchFilter, type: .location, origin: .system, sortStyle: .links, string: nil, region: region, localizedDescription: WMFLocalizedString("places-search-top-articles", value:"All top articles", comment:"A search suggestion for top articles"), searchResult: nil)
    }
    
    var articleFetchedResultsController = NSFetchedResultsController<WMFArticle>() {
        didSet {
            oldValue.delegate = nil
            for article in oldValue.fetchedObjects ?? [] {
                article.placesSortOrder = NSNumber(integerLiteral: 0)
            }
            do {
                try dataStore.viewContext.save()
                try articleFetchedResultsController.performFetch()
            } catch let fetchError {
                DDLogError("Error fetching articles for places: \(fetchError)")
            }
            updatePlaces()
            articleFetchedResultsController.delegate = self
        }
    }
    
    func isDistanceSignificant(betweenRegion searchRegion: MKCoordinateRegion, andRegion visibleRegion: MKCoordinateRegion) -> Bool {
        let distance = CLLocation(latitude: visibleRegion.center.latitude, longitude: visibleRegion.center.longitude).distance(from: CLLocation(latitude: searchRegion.center.latitude, longitude: searchRegion.center.longitude))
        
        let searchWidth = searchRegion.width
        let searchHeight = searchRegion.height
        let searchRegionMinDimension = min(searchWidth, searchHeight)
        
        guard searchRegionMinDimension > 0 else {
            return distance > 1000
        }
       
        let isDistanceSignificant = distance/searchRegionMinDimension > 0.33
        guard !isDistanceSignificant else {
            return true
        }
        
        let visibleWidth = visibleRegion.width
        let visibleHeight = visibleRegion.height
        
        guard searchWidth > 0, visibleWidth > 0, visibleHeight > 0, searchHeight > 0 else {
            return false
        }
        
        let widthRatio = visibleWidth/searchWidth
        let heightRatio = visibleHeight/searchHeight
        let ratio = min(widthRatio, heightRatio)
        return ratio > 1.33 || ratio < 0.67
    }

    func updateViewIfMapMovedSignificantly(forVisibleRegion visibleRegion: MKCoordinateRegion) {
        guard let searchRegion = currentSearchRegion else {
            redoSearchButton.isHidden = true
            return
        }
        
        let regionThatFits = region(thatFits: searchRegion)
        let movedSignificantly = isDistanceSignificant(betweenRegion: regionThatFits, andRegion: visibleRegion)
        DDLogDebug("movedSignificantly=\(movedSignificantly)")
        
        // Update Redo Search Button
        redoSearchButton.isHidden = !(movedSignificantly)

        if (movedSignificantly) {
            // Update Did You Mean Button
            hideDidYouMeanButton()
            
            // Clear count for Top Places
            _displayCountForTopPlaces = nil
        }
    }
    
    func performSearch(_ search: PlaceSearch) {
        guard !searching else {
            return
        }
        
        guard search.type != .nearby else {
            currentSearch = nil // will cause the default search to perform after re-centering
            recenterOnUserLocation(self)
            return
        }
        
        let done = {
            self.searching = false
            self.progressView.setProgress(1.0, animated: true)
            self.isProgressHidden = true
        }
        
        searching = true
        redoSearchButton.isHidden = true
        deselectAllAnnotations()
        updateSavedPlacesCountInCurrentMapRegionIfNecessary()
        hideDidYouMeanButton()
        
        let siteURL = search.siteURL ?? self.siteURL
        var searchTerm: String? = nil
        let sortStyle = search.sortStyle
        let region = search.region ?? mapRegion ?? mapView.region
        currentSearchRegion = region

        if (search.filter == .top && search.type == .location) {
            if (search.needsWikidataQuery) {
                performWikidataQuery(forSearch: search)
                return
            } else {
                // TODO: ARM: I don't understand this
                tracker?.wmf_logActionTapThrough(inContext: searchTrackerContext, contentType: AnalyticsContent(siteURL))
            }
        }
        
        if let currentMapRegion = mapRegion, isDistanceSignificant(betweenRegion: region, andRegion: currentMapRegion) {
            mapRegion = region
        } else if mapRegion == nil {
            mapRegion = region
        }
        
        searchTerm = search.string
        
        isProgressHidden = false
        progressView.setProgress(0, animated: false)
        perform(#selector(incrementProgress), with: nil, afterDelay: 0.3) // TODO: maybe not needed for saved articles
        
        switch search.filter {
        case .saved:
            tracker?.wmf_logAction("Saved_article_search", inContext: searchTrackerContext, contentType: AnalyticsContent(siteURL))
            
            let moc = dataStore.viewContext
            placeSearchService.performSearch(search, defaultSiteURL: siteURL, region: region, completion: { (result) in
                defer { done() }
                
                guard result.error == nil else {
                    DDLogError("Error fetching saved articles: \(result.error?.localizedDescription ?? "unknown error")")
                    return
                }
                guard let request = result.fetchRequest else {
                    DDLogError("Error fetching saved articles: fetchRequest was nil")
                    return
                }
                
                self.articleFetchedResultsController = NSFetchedResultsController<WMFArticle>(fetchRequest: request, managedObjectContext: self.dataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
                
                do {
                    let articlesToShow = try moc.fetch(request)
                    self.articleKeyToSelect = articlesToShow.first?.key
                    if articlesToShow.count > 0 {
                        if (self.currentSearch?.region == nil) {
                            self.currentSearchRegion = self.region(thatFits: articlesToShow)
                            self.mapRegion = self.currentSearchRegion
                        }
                    }
                    if articlesToShow.count == 0 {
                        self.wmf_showAlertWithMessage(WMFLocalizedString("places-no-saved-articles-have-location", value:"None of your saved articles have location information", comment:"Indicates to the user that none of their saved articles have location information"))
                    }
                } catch let error {
                    DDLogError("Error fetching saved articles: \(error.localizedDescription)")
                }
            })

        case .top:
            tracker?.wmf_logAction("Top_article_search", inContext: searchTrackerContext, contentType: AnalyticsContent(siteURL))
            
            placeSearchService.performSearch(search, defaultSiteURL: siteURL, region: region, completion: { (result) in
                defer { done() }
                
                guard result.error == nil else {
                    if let error = result.error {
                        WMFAlertManager.sharedInstance.showWarningAlert(result.error!.localizedDescription, sticky: false, dismissPreviousAlerts: true, tapCallBack: nil)
                        
                        let nserror = error as NSError
                        if (nserror.code == Int(WMFLocationSearchErrorCode.noResults.rawValue)) {
                            let completions = self.searchSuggestionController.searches[PlaceSearchSuggestionController.completionSection]
                            if (completions.count > 0) {
                                self.showDidYouMeanButton(search: completions[0])
                            }
                        }
                    } else {
                        WMFAlertManager.sharedInstance.showWarningAlert(
                            WMFLocalizedString("error-unknown", value: "An unknown error occurred", comment: "Message displayed when an unknown error occurred")
                            , sticky: false, dismissPreviousAlerts: true, tapCallBack: nil)
                    }
                    return
                }
                
                guard let locationResults = result.locationResults else {
                    assertionFailure("no error and missing location results")
                    return
                }
                
                self.updatePlaces(withSearchResults: locationResults)
            })
        }
    }
    
    func showDidYouMeanButton(search: PlaceSearch) {
        guard let description = search.localizedDescription else {
            DDLogError("Could not show Did You Mean button = no description for search:\n\(search)")
            return
        }
        
        DDLogDebug("Did you mean '\(String(describing: search.localizedDescription))'?")
        self.didYouMeanSearch = search
        self.didYouMeanButton.isHidden = false
        
        let title = String.localizedStringWithFormat(WMFLocalizedString("places-search-did-you-mean", value:"Did you mean %1$@?", comment:"Title displayed on a button shown when the current search has no results. %1$@ is replaced by the short description of the location of the most likely correction."), description)
        
        let buttonFont = redoSearchButton.titleLabel?.font
        let italicsFont = UIFont.italicSystemFont(ofSize: buttonFont?.pointSize ?? 15.0)
        let nsTitle = title as NSString
        let attributedTitle = NSMutableAttributedString(string: title)
        let descriptionRange = nsTitle.range(of: description)
        attributedTitle.addAttribute(NSFontAttributeName, value: italicsFont, range: descriptionRange)
        self.didYouMeanButton.setAttributedTitle(attributedTitle, for: .normal)
    }
    
    func hideDidYouMeanButton() {
        didYouMeanButton.isHidden = true
        didYouMeanSearch = nil
    }

    func performWikidataQuery(forSearch search: PlaceSearch) {
        let fail = {
            dispatchOnMainQueue({
                self.searching = false
                var newSearch = search
                newSearch.needsWikidataQuery = false
                self.currentSearch = newSearch
            })
        }
        guard let articleURL = search.searchResult?.articleURL(forSiteURL: siteURL) else {
            fail()
            return
        }
        
        wikidataFetcher.wikidataBoundingRegion(forArticleURL: articleURL, failure: { (error) in
            DDLogError("Error fetching bounding region from Wikidata: \(error)")
            fail()
        }, success: { (region) in
            dispatchOnMainQueue({
                self.searching = false
                var newSearch = search
                newSearch.needsWikidataQuery = false
                newSearch.region = region
                self.currentSearch = newSearch
            })
        })
    }
    
    func updatePlaces(withSearchResults searchResults: [MWKSearchResult]) {
        if let searchSuggestionArticleURL = currentSearch?.searchResult?.articleURL(forSiteURL: siteURL),
            let searchSuggestionArticleKey = (searchSuggestionArticleURL as NSURL?)?.wmf_articleDatabaseKey { // the user tapped an article in the search suggestions list, so we should select that
            articleKeyToSelect = searchSuggestionArticleKey
        } else if currentSearch?.filter == .top {
            if let centerCoordinate = currentSearch?.region?.center ?? mapRegion?.center {
                let center = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                var minDistance = CLLocationDistance(Double.greatestFiniteMagnitude)
                var resultToSelect: MWKSearchResult?
                for result in searchResults {
                    guard let location = result.location else {
                        continue
                    }
                    let distance = location.distance(from: center)
                    if distance < minDistance {
                        minDistance = distance
                        resultToSelect = result
                    }
                }
                let resultURL = resultToSelect?.articleURL(forSiteURL: siteURL)
                articleKeyToSelect = (resultURL as NSURL?)?.wmf_articleDatabaseKey
            } else {
                let firstResultURL = searchResults.first?.articleURL(forSiteURL: siteURL)
                articleKeyToSelect = (firstResultURL as NSURL?)?.wmf_articleDatabaseKey
            }
        }
        
        var foundKey = false
        var keysToFetch: [String] = []
        var sort = 1
        for result in searchResults {
            guard let displayTitle = result.displayTitle,
                let articleURL = (siteURL as NSURL).wmf_URL(withTitle: displayTitle),
                let article = self.dataStore.viewContext.fetchOrCreateArticle(with: articleURL, updatedWith: result),
                let _ = article.quadKey,
                let articleKey = article.key else {
                    continue
            }
            article.placesSortOrder = NSNumber(value: sort)
            if articleKeyToSelect != nil && articleKeyToSelect == articleKey {
                foundKey = true
            }
            keysToFetch.append(articleKey)
            sort += 1
        }
        
        if !foundKey, let keyToFetch = articleKeyToSelect, let URL = URL(string: keyToFetch), let searchResult = currentSearch?.searchResult {
            dataStore.viewContext.fetchOrCreateArticle(with: URL, updatedWith: searchResult)
            keysToFetch.append(keyToFetch)
        }
        
        let request = WMFArticle.fetchRequest()
        request.predicate = NSPredicate(format: "key in %@", keysToFetch)
        request.sortDescriptors = [NSSortDescriptor(key: "placesSortOrder", ascending: true)]
        articleFetchedResultsController = NSFetchedResultsController<WMFArticle>(fetchRequest: request, managedObjectContext: dataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }
    
    func updatePlaces() {
        listView.reloadData()
        currentGroupingPrecision = 0
        regroupArticlesIfNecessary(forVisibleRegion: mapRegion ?? mapView.region)
        if currentSearch?.region == nil { // this means the search was done in the curent map region and the map won't move
            selectVisibleKeyToSelectIfNecessary()
        }
    }
    
    func updateSavedPlacesCountInCurrentMapRegionIfNecessary() {
        guard _displayCountForTopPlaces == nil else {
            return
        }
        
        if let currentSearch = self.currentSearch, currentSearchFilter == .saved {
            var tempSearch = PlaceSearch(filter: .top, type: currentSearch.type, origin: .system, sortStyle: currentSearch.sortStyle, string: nil, region: mapView.region, localizedDescription: nil, searchResult: nil)
            tempSearch.needsWikidataQuery = false
            
            placeSearchService.performSearch(tempSearch, defaultSiteURL: siteURL, region: mapView.region, completion: { (searchResult) in
                guard let locationResults = searchResult.locationResults else {
                    return
                }
                DDLogDebug("got \(locationResults.count) top places!")
                self._displayCountForTopPlaces = locationResults.count
            })
        }
    }

    
    @IBAction func redoSearch(_ sender: Any) {
        guard let search = currentSearch else {
            return
        }
        
        redoSearchButton.isHidden = true
        
        if isDefaultSearch(search) || (search.type == .location && search.filter == .top) {
            performDefaultSearch(withRegion: mapView.region)
        } else {
            currentSearch = PlaceSearch(filter: currentSearchFilter, type: search.type, origin: .user, sortStyle: search.sortStyle, string: search.string, region: nil, localizedDescription: search.localizedDescription, searchResult: nil)
        }
    }
    
    @IBAction func didYouMean(_ sender: Any) {
        defer {
            hideDidYouMeanButton()
        }
        
        guard let search = self.didYouMeanSearch else {
            DDLogError("Did You Mean search is unset")
            return
        }
        
        performSearch(search)
    }
    
    // MARK: - Display Actions
    
    func deselectAllAnnotations() {
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: true)
        }
    }
    
    var useOverlay: Bool {
        get {
            return traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular
        }
    }
    
    func updateLayout(_ traitCollection: UITraitCollection, animated: Bool) {
        if useOverlay {
            switch viewMode {
            case .search:
                viewMode = .searchOverlay
            case .list:
                fallthrough
            case .map:
                viewMode = .listOverlay
            default:
                break
            }
        } else {
            switch viewMode {
            case .searchOverlay:
                viewMode = .search
            case .listOverlay:
                viewMode = .map
            default:
                break
            }
        }
    }
    
    enum ViewMode {
        case none
        case map
        case list
        case search
        case listOverlay
        case searchOverlay
    }
    
    fileprivate var overlaySliderPanGestureRecognizer: UIPanGestureRecognizer?
    
    func addSearchBarToNavigationBar(animated: Bool) {
        //   Borrowed from https://developer.apple.com/library/content/samplecode/NavBar/Introduction/Intro.html
        extendedNavBarView.isHidden = false
        wmf_updateNavigationBar(removeUnderline: true)

        let searchBarHeight: CGFloat = 32
        let searchBarLeftPadding: CGFloat = 7.5
        let searchBarRightPadding: CGFloat = 2.5
        
        searchBar = titleViewSearchBar
        
        filterSelectorView.frame = CGRect(x: searchBarLeftPadding, y: 0, width: view.bounds.size.width - searchBarLeftPadding - searchBarRightPadding, height: searchBarHeight)
        filterSelectorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        let titleView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.size.width, height: searchBarHeight))
        titleView.addSubview(filterSelectorView)
        navigationItem.titleView = titleView
        
        if let panGR = overlaySliderPanGestureRecognizer {
            view.removeGestureRecognizer(panGR)
        }
    }
    
    func removeSearchBarFromNavigationBar(animated: Bool) {
        extendedNavBarView.isHidden = true
        wmf_updateNavigationBar(removeUnderline: false)
        
        listAndSearchOverlayFilterSelectorContainerView.addSubview(filterSelectorView)
        filterSelectorView.frame = listAndSearchOverlayFilterSelectorContainerView.bounds
        
        searchBar = listAndSearchOverlaySearchBar
        
        let panGR = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGR.delegate = self
        view.addGestureRecognizer(panGR)
        overlaySliderPanGestureRecognizer = panGR
    }
    
    var initialOverlayHeightForPan: CGFloat?
    
    let overlayMidHeight: CGFloat = 388
    var overlayMinHeight: CGFloat {
        get {
            return listAndSearchOverlayFilterSelectorContainerHeightConstraint.constant + listAndSearchOverlaySearchHeightConstraint.constant + listAndSearchOverlaySliderHeightConstraint.constant
        }
    }
    var overlayMaxHeight: CGFloat {
        get {
            return view.bounds.size.height - listAndSearchOverlayContainerView.frame.minY - listAndSearchOverlayBottomConstraint.constant
        }
    }

    enum OverlayState {
        case min
        case mid
        case max
    }
    
    func set(overlayState: OverlayState, withVelocity velocity: CGFloat, animated: Bool) {
        let currentHeight = listAndSearchOverlayHeightConstraint.constant
        let newHeight: CGFloat
        switch overlayState {
        case .min:
            newHeight = overlayMinHeight
        case .max:
            newHeight = overlayMaxHeight
        default:
            newHeight = overlayMidHeight
        }
        let springVelocity = velocity / (newHeight - currentHeight)
        self.view.layoutIfNeeded()
        let animations = {
            self.listAndSearchOverlayHeightConstraint.constant = newHeight
            self.view.layoutIfNeeded()
        }
        let duration: TimeInterval = 0.5
        self.overlayState = overlayState
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: springVelocity, options: [.allowUserInteraction], animations: animations, completion: { (didFinish) in
            if overlayState == .max {
                self.listAndSearchOverlayHeightConstraint.isActive = false
                self.listAndSearchOverlayBottomConstraint.isActive = true
            } else {
                self.listAndSearchOverlayHeightConstraint.isActive = true
                self.listAndSearchOverlayBottomConstraint.isActive = false
            }
        })
    }
    
    var overlayState = OverlayState.mid
    
    
    func handlePanGesture(_ panGR: UIPanGestureRecognizer) {
        let minHeight = overlayMinHeight
        let maxHeight = overlayMaxHeight
        let midHeight = overlayMidHeight
        switch panGR.state {
        case .possible:
            fallthrough
        case .began:
            fallthrough
        case .changed:
            let initialHeight: CGFloat
            if let height = initialOverlayHeightForPan {
                initialHeight = height
            } else {
                if (overlayState == .max) {
                    listAndSearchOverlayHeightConstraint.constant = listAndSearchOverlayContainerView.frame.height
                }
                initialHeight = listAndSearchOverlayHeightConstraint.constant
                initialOverlayHeightForPan = initialHeight
                listAndSearchOverlayHeightConstraint.isActive = true
                listAndSearchOverlayBottomConstraint.isActive = false
            }
            listAndSearchOverlayHeightConstraint.constant = max(minHeight, initialHeight + panGR.translation(in: view).y)
        case .ended:
            fallthrough
        case .failed:
            fallthrough
        case .cancelled:
            let currentHeight = listAndSearchOverlayHeightConstraint.constant
            let newState: OverlayState
            if currentHeight <= midHeight {
                let min: Bool = currentHeight - minHeight <= midHeight - currentHeight
                if min {
                    newState = .min
                } else {
                    newState = .mid
                }
            } else {
                let mid: Bool = currentHeight - midHeight <= maxHeight - currentHeight
                if mid {
                    newState = .mid
                } else {
                    newState = .max
                }
            }
            set(overlayState: newState, withVelocity: panGR.velocity(in: view).y, animated: true)
            initialOverlayHeightForPan = nil
            break
        }
    }
    
    var isSearchBarInNavigationBar: Bool? {
        didSet{
            guard let newValue = isSearchBarInNavigationBar, oldValue != newValue else {
                return
            }
            if newValue {
                addSearchBarToNavigationBar(animated: false)
            } else {
                removeSearchBarFromNavigationBar(animated: false)
            }
        }
    }

    
    fileprivate func updateTraitBasedViewMode() {
        //forces an update
        let oldViewMode = self.viewMode
        self.viewMode = .none
        self.viewMode = oldViewMode
    }
    
    var isOverlaySearchButtonHidden = true {
        didSet {
            let isHidden = isOverlaySearchButtonHidden
            let animations = {
                if (isHidden) { // always disable the old constraint before enabling the new one to avoid autolayout errors
                    self.listAndSearchOverlaySearchCancelButtonShowConstraint.isActive = false
                    self.listAndSearchOverlaySearchCancelButtonHideConstraint.isActive = true
                } else {
                    self.listAndSearchOverlaySearchCancelButtonHideConstraint.isActive = false
                    self.listAndSearchOverlaySearchCancelButtonShowConstraint.isActive = true
                }
            }
            if (isHidden)  {
                animations()
            } else {
                listAndSearchOverlayContainerView.layoutIfNeeded()
                UIView.animate(withDuration: 0.3) {
                    animations()
                    self.listAndSearchOverlayContainerView.layoutIfNeeded()
                }
            }
        }
    }
    
    var isViewModeOverlay: Bool {
        get {
            return traitBasedViewMode == .listOverlay || traitBasedViewMode == .searchOverlay
        }
    }
    
    var traitBasedViewMode: ViewMode = .none {
        didSet {
            guard oldValue != traitBasedViewMode else {
                return
            }
            if oldValue == .search && viewMode != .search {
                UIView.performWithoutAnimation {
                    searchBarToCloseTrailingConstraint.isActive = false
                    closeSearchButton.isHidden = true
                    searchBarToMapListToggleTrailingConstraint.isActive = true
                    mapListToggle.isHidden = false
                    searchBar?.layoutIfNeeded()
                }
            } else if oldValue != .search && viewMode == .search {
                UIView.performWithoutAnimation {
                    searchBarToMapListToggleTrailingConstraint.isActive = false
                    mapListToggle.isHidden = true
                    searchBarToCloseTrailingConstraint.isActive = true
                    closeSearchButton.isHidden = false
                    searchBar?.layoutIfNeeded()
                }
            }
            switch traitBasedViewMode {
            case .listOverlay:
                isSearchBarInNavigationBar = false
                deselectAllAnnotations()
                updateDistanceFromUserOnVisibleCells()
                logListViewImpressionsForVisibleCells()
                mapView.isHidden = false
                listView.isHidden = false
                searchSuggestionView.isHidden = true
                listAndSearchOverlayContainerView.isHidden = false
                isOverlaySearchButtonHidden = true
                filterSelectorView.button.isEnabled = true
            case .list:
                isSearchBarInNavigationBar = true
                deselectAllAnnotations()
                updateDistanceFromUserOnVisibleCells()
                logListViewImpressionsForVisibleCells()
                mapView.isHidden = true
                listView.isHidden = false
                searchSuggestionView.isHidden = true
                listAndSearchOverlayContainerView.isHidden = false
                filterSelectorView.button.isEnabled = true
            case .searchOverlay:
                if overlayState == .min {
                    set(overlayState: .mid, withVelocity: 0, animated: true)
                }
                isOverlaySearchButtonHidden = false
                isSearchBarInNavigationBar = false
                mapView.isHidden = false
                listView.isHidden = true
                searchSuggestionView.isHidden = false
                listAndSearchOverlayContainerView.isHidden = false
                filterSelectorView.button.isEnabled = false
            case .search:
                isSearchBarInNavigationBar = true
                mapView.isHidden = true
                listView.isHidden = true
                searchSuggestionView.isHidden = false
                listAndSearchOverlayContainerView.isHidden = false
                filterSelectorView.button.isEnabled = false
            case .map:
                fallthrough
            default:
                isSearchBarInNavigationBar = true
                mapView.isHidden = false
                listView.isHidden = true
                searchSuggestionView.isHidden = true
                listAndSearchOverlayContainerView.isHidden = true
                filterSelectorView.button.isEnabled = true
            }
            recenterOnUserLocationButton.isHidden = mapView.isHidden
            if (mapView.isHidden) {
                redoSearchButton.isHidden = true
            } else {
                updateViewIfMapMovedSignificantly(forVisibleRegion: mapView.region)
            }
            updateSearchFilterTitle()
        }
    }

    var viewMode: ViewMode = .none {
        didSet {
            guard oldValue != viewMode, viewMode != .none else {
                return
            }
            switch viewMode {
            case .list:
                traitBasedViewMode = useOverlay ? .listOverlay : .list
            case .search:
                traitBasedViewMode = useOverlay ? .searchOverlay : .search
            case .map:
                fallthrough
            default:
                traitBasedViewMode = useOverlay ? .listOverlay : .map
            }
        }
    }
    
    var currentSearchFilter: PlaceFilterType = .top { // TODO: remember last setting?
        didSet {
            guard oldValue != currentSearchFilter else {
                return
            }
            
            updateSearchFilterTitle()
            
            switch viewMode {
            case .search:
                updateSearchSuggestions(withCompletions: [], isSearchDone: false)
            default:
                if let currentSearch = self.currentSearch {
                    self.currentSearch = PlaceSearch(filter: currentSearchFilter, type: currentSearch.type, origin: .system, sortStyle: currentSearch.sortStyle, string: currentSearch.string, region: nil, localizedDescription: currentSearch.localizedDescription, searchResult: currentSearch.searchResult, siteURL: currentSearch.siteURL)
                }
            }
        }
    }
    

    func updateViewModeFromSegmentedControl() {
        switch mapListToggle.selectedSegmentIndex {
        case 0:
            viewMode = .map
        default:
            viewMode = .list
        }
    }
    
    func selectArticlePlace(_ articlePlace: ArticlePlace) {
        mapView.selectAnnotation(articlePlace, animated: articlePlace.identifier != previouslySelectedArticlePlaceIdentifier)
        previouslySelectedArticlePlaceIdentifier = articlePlace.identifier
    }

    // MARK: - Search History
    
    fileprivate func searchHistoryGroup(forFilter: PlaceFilterType) -> String {
        let searchHistoryGroup = "PlaceSearch"
        return "\(searchHistoryGroup).\(forFilter.stringValue)"
    }
    
    fileprivate func currentSearchHistoryGroup() -> String {
        return searchHistoryGroup(forFilter: currentSearchFilter)
    }
    
    func saveToHistory(search: PlaceSearch) {
        guard search.origin == .user else {
            DDLogDebug("not saving system search to history")
            return
        }
        
        do {
            let moc = dataStore.viewContext
            if let keyValue = keyValue(forPlaceSearch: search, inManagedObjectContext: moc) {
                keyValue.date = Date()
            } else if let entity = NSEntityDescription.entity(forEntityName: "WMFKeyValue", in: moc) {
                let keyValue =  WMFKeyValue(entity: entity, insertInto: moc)
                keyValue.key = search.key
                keyValue.group = currentSearchHistoryGroup()
                keyValue.date = Date()
                keyValue.value = search.dictionaryValue as NSObject
            }
            try moc.save()
        } catch let error {
            DDLogError("error saving to place search history: \(error.localizedDescription)")
        }
    }
    
    func clearSearchHistory() {
        do {
            let moc = dataStore.viewContext
            let request = WMFKeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "group == %@", currentSearchHistoryGroup())
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let results = try moc.fetch(request)
            for result in results {
                moc.delete(result)
            }
            try moc.save()
        } catch let error {
            DDLogError("Error clearing recent place searches: \(error)")
        }
    }
    
    func keyValue(forPlaceSearch placeSearch: PlaceSearch, inManagedObjectContext moc: NSManagedObjectContext) -> WMFKeyValue? {
        var keyValue: WMFKeyValue?
        do {
            let key = placeSearch.key
            let request = WMFKeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@ && group == %@", key, currentSearchHistoryGroup())
            request.fetchLimit = 1
            let results = try moc.fetch(request)
            keyValue = results.first
        } catch let error {
            DDLogError("Error fetching place search key value: \(error.localizedDescription)")
        }
        return keyValue
    }
    
    // MARK: - Location Access
    
    func promptForLocationAccess() {
        let enableLocationVC = EnableLocationViewController(nibName: "EnableLocationViewController", bundle: nil)
        enableLocationVC.view.tintColor = view.tintColor
        enableLocationVC.modalPresentationStyle = .popover
        enableLocationVC.preferredContentSize = enableLocationVC.view.systemLayoutSizeFitting(CGSize(width: enableLocationVC.view.bounds.size.width, height: UILayoutFittingCompressedSize.height), withHorizontalFittingPriority: UILayoutPriorityRequired, verticalFittingPriority: UILayoutPriorityFittingSizeLevel)
        enableLocationVC.popoverPresentationController?.delegate = self
        enableLocationVC.popoverPresentationController?.sourceView = view
        enableLocationVC.popoverPresentationController?.canOverlapSourceViewRect = true
        enableLocationVC.popoverPresentationController?.sourceRect = view.bounds
        enableLocationVC.popoverPresentationController?.permittedArrowDirections = []
        enableLocationVC.delegate = self
        present(enableLocationVC, animated: true, completion: {
            
        })
    }
    
    
    // MARK: - Progress
    
    func incrementProgress() {
        guard !isProgressHidden && progressView.progress <= 0.69 else {
            return
        }
        
        let rand = 0.15 + Float(arc4random_uniform(15))/100
        progressView.setProgress(progressView.progress + rand, animated: true)
        perform(#selector(incrementProgress), with: nil, afterDelay: 0.3)
    }
    
    func hideProgress() {
        UIView.animate(withDuration: 0.3, animations: { self.progressView.alpha = 0 } )
    }
    
    func showProgress() {
        progressView.alpha = 1
    }
    
    var isProgressHidden: Bool = false {
        didSet{
            if isProgressHidden {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showProgress), object: nil)
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(incrementProgress), object: nil)
                perform(#selector(hideProgress), with: nil, afterDelay: 0.7)
            } else {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideProgress), object: nil)
                showProgress()
            }
        }
    }
    
    // MARK: - Place Grouping
    
    fileprivate var groupingTaskGroup: WMFTaskGroup?
    fileprivate var needsRegroup = false
    fileprivate var showingAllImages = false
    fileprivate var greaterThanOneArticleGroupCount = 0
    
    struct ArticleGroup {
        var articles: [WMFArticle] = []
        var latitudeSum: QuadKeyDegrees = 0
        var longitudeSum: QuadKeyDegrees = 0
        var latitudeAdjustment: QuadKeyDegrees = 0
        var longitudeAdjustment: QuadKeyDegrees = 0
        var baseQuadKey: QuadKey = 0
        var baseQuadKeyPrecision: QuadKeyPrecision = 0
        var location: CLLocation {
            get {
                return CLLocation(latitude: (latitudeSum + latitudeAdjustment)/CLLocationDegrees(articles.count), longitude: (longitudeSum + longitudeAdjustment)/CLLocationDegrees(articles.count))
            }
        }
        
        init () {
            
        }
        
        init(article: WMFArticle) {
            articles = [article]
            latitudeSum = article.coordinate?.latitude ?? 0
            longitudeSum = article.coordinate?.longitude ?? 0
            baseQuadKey = article.quadKey ?? 0
            baseQuadKeyPrecision = QuadKeyPrecision.maxPrecision
        }
    }

    
    func merge(group: ArticleGroup, key: String, groups: [String: ArticleGroup], groupingDistance: CLLocationDistance) -> Set<String> {
        var toMerge = Set<String>()
        if let keyToSelect = articleKeyToSelect, group.articles.first?.key == keyToSelect {
            //no grouping with the article to select
            return toMerge
        }
        
        let baseQuadKey = group.baseQuadKey
        let baseQuadKeyPrecision = group.baseQuadKeyPrecision
        let baseQuadKeyCoordinate = QuadKeyCoordinate(quadKey: baseQuadKey, precision: baseQuadKeyPrecision)
        
        if baseQuadKeyCoordinate.latitudePart > 2 && baseQuadKeyCoordinate.longitudePart > 1 {
            for t: Int64 in -1...1 {
                for n: Int64 in -1...1 {
                    guard t != 0 || n != 0 else {
                        continue
                    }
                    let latitudePart = QuadKeyPart(Int64(baseQuadKeyCoordinate.latitudePart) + 2*t)
                    let longitudePart = QuadKeyPart(Int64(baseQuadKeyCoordinate.longitudePart) + n)
                    let adjacentBaseQuadKey = QuadKey(latitudePart: latitudePart, longitudePart: longitudePart, precision: baseQuadKeyPrecision)
                    let adjacentKey = "\(adjacentBaseQuadKey)|\(adjacentBaseQuadKey + 1)"
                    guard let adjacentGroup = groups[adjacentKey] else {
                        continue
                    }
                    if let keyToSelect = articleKeyToSelect, adjacentGroup.articles.first?.key == keyToSelect {
                        //no grouping with the article to select
                        continue
                    }
                    guard group.articles.count > 1 || adjacentGroup.articles.count > 1 else {
                        continue
                    }
                    let location = group.location
                    let distance = adjacentGroup.location.distance(from: location)
                    let distanceToCheck = group.articles.count == 1 || adjacentGroup.articles.count == 1 ? 0.25*groupingDistance : groupingDistance
                    if distance < distanceToCheck {
                        toMerge.insert(adjacentKey)
                        var newGroups = groups
                        newGroups.removeValue(forKey: key)
                        let others = merge(group: adjacentGroup, key: adjacentKey, groups: newGroups, groupingDistance: groupingDistance)
                        toMerge.formUnion(others)
                    }
                }
            }
        }
        return toMerge
    }
    
    func regroupArticlesIfNecessary(forVisibleRegion visibleRegion: MKCoordinateRegion) {
        guard groupingTaskGroup == nil else {
            needsRegroup = true
            return
        }
        assert(Thread.isMainThread)
        
        guard let searchRegion = currentSearchRegion else {
            return
        }
        
        let deltaLon = visibleRegion.span.longitudeDelta
        let lowestPrecision = QuadKeyPrecision(deltaLongitude: deltaLon)
        let searchDeltaLon = searchRegion.span.longitudeDelta
        let lowestSearchPrecision = QuadKeyPrecision(deltaLongitude: searchDeltaLon)
        var groupingAggressiveness: CLLocationDistance = 0.67
        let groupingPrecisionDelta: QuadKeyPrecision = isViewModeOverlay ? 5 : 4
        let maxPrecision: QuadKeyPrecision = isViewModeOverlay ? 18 : 17
        let minGroupCount = 3
        if lowestPrecision + groupingPrecisionDelta <= lowestSearchPrecision {
            groupingAggressiveness += 0.3
        }
        let currentPrecision = lowestPrecision + groupingPrecisionDelta
        let groupingPrecision = min(maxPrecision, currentPrecision)

        guard groupingPrecision != currentGroupingPrecision else {
            return
        }
        
        let taskGroup = WMFTaskGroup()
        groupingTaskGroup = taskGroup
        
        let groupingDeltaLatitude = groupingPrecision.deltaLatitude
        let groupingDeltaLongitude = groupingPrecision.deltaLongitude
        
        let centerLat = searchRegion.center.latitude
        let centerLon = searchRegion.center.longitude
        let groupingDistanceLocation = CLLocation(latitude:centerLat + groupingDeltaLatitude, longitude: centerLon + groupingDeltaLongitude)
        let centerLocation = CLLocation(latitude:centerLat, longitude: centerLon)
        let groupingDistance = groupingAggressiveness * groupingDistanceLocation.distance(from: centerLocation)
        
        var previousPlaceByArticle: [String: ArticlePlace] = [:]
        
        var annotationsToRemove: [Int:ArticlePlace] = [:]
        
        for annotation in mapView.annotations {
            guard let place = annotation as? ArticlePlace else {
                continue
            }
            
            annotationsToRemove[place.identifier] = place
            
            for article in place.articles {
                guard let key = article.key else {
                    continue
                }
                previousPlaceByArticle[key] = place
            }
        }
        
        var groups: [String: ArticleGroup] = [:]
        var splittableGroups: [String: ArticleGroup] = [:]
        for article in articleFetchedResultsController.fetchedObjects ?? [] {
            guard let quadKey = article.quadKey else {
                continue
            }
            var group: ArticleGroup
            let adjustedQuadKey: QuadKey
            var key: String
            if groupingPrecision < maxPrecision && (articleKeyToSelect == nil || article.key != articleKeyToSelect) {
                adjustedQuadKey = quadKey.adjusted(downBy: QuadKeyPrecision.maxPrecision - groupingPrecision)
                let baseQuadKey = adjustedQuadKey - adjustedQuadKey % 2
                key = "\(baseQuadKey)|\(baseQuadKey + 1)" // combine neighboring vertical keys
                group = groups[key] ?? ArticleGroup()
                group.baseQuadKey = baseQuadKey
                group.baseQuadKeyPrecision = groupingPrecision
            } else {
                group = ArticleGroup()
                adjustedQuadKey = quadKey
                key = "\(adjustedQuadKey)"
                if var existingGroup = groups[key] {
                    let existingGroupArticleKey = existingGroup.articles.first?.key ?? ""
                    let existingGroupTitle = existingGroup.articles.first?.displayTitle ?? ""
                    existingGroup.latitudeAdjustment = 0.0001 * CLLocationDegrees(existingGroupArticleKey.hash) / CLLocationDegrees(Int.max)
                    existingGroup.longitudeAdjustment = 0.0001 * CLLocationDegrees(existingGroupTitle.hash) / CLLocationDegrees(Int.max)
                    groups[key] = existingGroup
                    
                    let articleKey = article.key ?? ""
                    let articleTitle = article.displayTitle ?? ""
                    group.latitudeAdjustment = 0.0001 * CLLocationDegrees(articleKey.hash) / CLLocationDegrees(Int.max)
                    group.longitudeAdjustment = 0.0001 * CLLocationDegrees(articleTitle.hash) / CLLocationDegrees(Int.max)
                    key = articleKey
                }
                group.baseQuadKey = quadKey
                group.baseQuadKeyPrecision = QuadKeyPrecision.maxPrecision
            }
            group.articles.append(article)
            let coordinate = QuadKeyCoordinate(quadKey: quadKey)
            group.latitudeSum += coordinate.latitude
            group.longitudeSum += coordinate.longitude
            groups[key] = group
            if group.articles.count > 1 {
                if group.articles.count < minGroupCount {
                    splittableGroups[key] = group
                } else {
                    splittableGroups[key] = nil
                }
            }
        }
        
        
        for (key, group) in splittableGroups {
            for (index, article) in group.articles.enumerated() {
                groups[key + ":\(index)"] = ArticleGroup(article: article)
            }
            groups.removeValue(forKey: key)
        }
        
        greaterThanOneArticleGroupCount = 0
        let keys = groups.keys
        for key in keys {
            guard var group = groups[key] else {
                continue
            }
            
            if groupingPrecision < maxPrecision {
                let toMerge = merge(group: group, key: key, groups: groups, groupingDistance: groupingDistance)
                for adjacentKey in toMerge {
                    guard let adjacentGroup = groups[adjacentKey] else {
                        continue
                    }
                    group.articles.append(contentsOf: adjacentGroup.articles)
                    group.latitudeSum += adjacentGroup.latitudeSum
                    group.longitudeSum += adjacentGroup.longitudeSum
                    groups.removeValue(forKey: adjacentKey)
                }
                
                
                if group.articles.count > 1 {
                    greaterThanOneArticleGroupCount += 1
                }
            }
            
            var nextCoordinate: CLLocationCoordinate2D?
            var coordinate = group.location.coordinate
            
            let identifier = ArticlePlace.identifierForArticles(articles: group.articles)
            
            //check for identical place already on the map
            if let _ = annotationsToRemove.removeValue(forKey: identifier) {
                continue
            }
            
            if group.articles.count == 1 {
                if let article = group.articles.first, let key = article.key, let previousPlace = previousPlaceByArticle[key] {
                    nextCoordinate = coordinate
                    coordinate = previousPlace.coordinate
                    if let thumbnailURL = article.thumbnailURL {
                        imageController.prefetch(withURL: thumbnailURL)
                    }
                }
                
            } else {
                let groupCount = group.articles.count
                for article in group.articles {
                    guard let key = article.key,
                        let previousPlace = previousPlaceByArticle[key] else {
                            continue
                    }
                    
                    guard previousPlace.articles.count < groupCount else {
                            nextCoordinate = coordinate
                            coordinate = previousPlace.coordinate
                        break
                    }
                    
                    guard annotationsToRemove.removeValue(forKey: previousPlace.identifier) != nil else {
                        continue
                    }
                    
                    let placeView = mapView.view(for: previousPlace)
                    taskGroup.enter()
                    self.countOfAnimatingAnnotations += 1
                    UIView.animate(withDuration:animationDuration, delay: 0, options: [.allowUserInteraction], animations: {
                        placeView?.alpha = 0
                        if (previousPlace.articles.count > 1) {
                            placeView?.transform = CGAffineTransform(scaleX: self.animationScale, y: self.animationScale)
                        }
                        previousPlace.coordinate = coordinate
                    }, completion: { (finished) in
                        taskGroup.leave()
                        self.mapView.removeAnnotation(previousPlace)
                        self.countOfAnimatingAnnotations -= 1
                    })
                }
            }

            
            guard let place = ArticlePlace(coordinate: coordinate, nextCoordinate: nextCoordinate, articles: group.articles, identifier: identifier) else {
                continue
            }
            
            mapView.addAnnotation(place)
            
            groups.removeValue(forKey: key)
        }
        
        for (_, annotation) in annotationsToRemove {
            let placeView = mapView.view(for: annotation)
            taskGroup.enter()
            self.countOfAnimatingAnnotations += 1
            UIView.animate(withDuration: 0.5*animationDuration, animations: {
                placeView?.transform = CGAffineTransform(scaleX: self.animationScale, y: self.animationScale)
                placeView?.alpha = 0
            }, completion: { (finished) in
                taskGroup.leave()
                self.mapView.removeAnnotation(annotation)
                self.countOfAnimatingAnnotations -= 1
            })
        }
        currentGroupingPrecision = groupingPrecision
        if greaterThanOneArticleGroupCount > 0 {
            set(shouldShowAllImages: false)
        }
        taskGroup.waitInBackground {
            self.groupingTaskGroup = nil
            self.selectVisibleKeyToSelectIfNecessary()
            if (self.needsRegroup) {
                self.needsRegroup = false
                self.regroupArticlesIfNecessary(forVisibleRegion: self.mapRegion ?? self.mapView.region)
            }
        }
    }
    
    // MARK: - Article Popover
    
    func showPopover(forAnnotationView annotationView: MapAnnotationView) {
        guard let place = annotationView.annotation as? ArticlePlace else {
            return
        }
        
        guard let article = place.articles.first,
            let coordinate = article.coordinate,
            let articleKey = article.key else {
                return
        }
        
        guard selectedArticlePopover == nil else {
            return
        }

        if isViewModeOverlay, let indexPath = articleFetchedResultsController.indexPath(forObject: article) {
            listView.scrollToRow(at: indexPath, at: .top, animated: true)
        }
        
        let articleVC = ArticlePopoverViewController(article)
        articleVC.delegate = self
        articleVC.view.tintColor = view.tintColor
        articleVC.configureView(withTraitCollection: traitCollection)
        
        let articleLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if locationManager.isUpdating {
            let userLocation = locationManager.location
            let distance = articleLocation.distance(from: userLocation)
            let distanceString = MKDistanceFormatter().string(fromDistance: distance)
            articleVC.descriptionLabel.text = distanceString
        } else {
            articleVC.descriptionLabel.text = nil
        }
        
        articleVC.view.alpha = 0
        addChildViewController(articleVC)
    
        view.insertSubview(articleVC.view, belowSubview: extendedNavBarView)
        articleVC.didMove(toParentViewController: self)
        
        let size = articleVC.view.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
        articleVC.preferredContentSize = size
        selectedArticlePopover = articleVC
        selectedArticleAnnotationView = annotationView
        selectedArticleKey = articleKey
        
        adjustLayout(ofPopover: articleVC, withSize:size, viewSize:view.bounds.size, forAnnotationView: annotationView)
        articleVC.view.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        articleVC.view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: popoverFadeDuration) {
            articleVC.view.transform = CGAffineTransform.identity
            articleVC.view.alpha = 1
        }
        
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, articleVC.view)

        tracker?.wmf_logActionImpression(inContext: mapTrackerContext, contentType: article)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { (context) in
            if let popover = self.selectedArticlePopover,
                let annotationView = self.selectedArticleAnnotationView {
                self.adjustLayout(ofPopover: popover, withSize: popover.preferredContentSize, viewSize: size, forAnnotationView: annotationView)
            }
            if self.isSearchFilterDropDownShowing {
                self.isSearchFilterDropDownShowing = false
            }
            self.updateTraitBasedViewMode()
        }, completion: nil)
    }
    
    func dismissCurrentArticlePopover() {
        guard let popover = selectedArticlePopover else {
            return
        }
        UIView.animate(withDuration: popoverFadeDuration, animations: {
            popover.view.alpha = 0
            popover.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { (done) in
            popover.willMove(toParentViewController: nil)
            popover.view.removeFromSuperview()
            popover.removeFromParentViewController()
        }
        selectedArticlePopover = nil
        selectedArticleAnnotationView = nil
    }
    
    func articlePopoverViewController(articlePopoverViewController: ArticlePopoverViewController, didSelectAction action: WMFArticleAction) {
        perform(action: action, onArticle: articlePopoverViewController.article)
    }
    
    func perform(action: WMFArticleAction, onArticle article: WMFArticle) {
        guard let url = article.url else {
            return
        }
        let context = viewMode == .list ? listTrackerContext : mapTrackerContext
        switch action {
        case .read:
            tracker?.wmf_logActionTapThrough(inContext: context, contentType: article)
            wmf_pushArticle(with: url, dataStore: dataStore, animated: true)
            if navigationController?.isNavigationBarHidden ?? false {
                navigationController?.setNavigationBarHidden(false, animated: true)
            }

            break
        case .save:
            let didSave = dataStore.savedPageList.toggleSavedPage(for: url)
            if didSave {
                tracker?.wmf_logActionSave(inContext: context, contentType: article)
            }else {
                tracker?.wmf_logActionUnsave(inContext: context, contentType: article)
            }
            break
        case .share:
            tracker?.wmf_logActionShare(inContext: context, contentType: article)
            var activityItems : [Any] = [url]
            if let mapItem = article.mapItem {
                activityItems.append(mapItem)
            }
            let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: [TUSafariActivity(), WMFOpenInMapsActivity(), WMFGetDirectionsInMapsActivity()])
            activityVC.popoverPresentationController?.sourceView = view
            var sourceRect = view.bounds
            if let shareButton = selectedArticlePopover?.shareButton {
                sourceRect = view.convert(shareButton.frame, from: shareButton.superview)
            }
            activityVC.popoverPresentationController?.sourceRect = sourceRect
            present(activityVC, animated: true, completion: nil)
            break
        case .none:
            fallthrough
        default:
            break
        }
    }
    
    enum PopoverLocation {
        case top
        case bottom
        case left
        case right
    }
    
    func adjustLayout(ofPopover articleVC: ArticlePopoverViewController, withSize popoverSize: CGSize, viewSize: CGSize, forAnnotationView annotationView: MapAnnotationView) {
        var preferredLocations = [PopoverLocation]()
        
        
        let annotationSize = annotationView.frame.size
        let spacing: CGFloat = 5
        let annotationCenter = view.convert(annotationView.center, from: mapView)
        
        if isViewModeOverlay {
            if UIApplication.shared.wmf_isRTL {
                if annotationCenter.x >= listAndSearchOverlayContainerView.frame.minX {
                    preferredLocations = [.bottom, .left, .right, .top]
                } else {
                    preferredLocations = [.left, .bottom, .top, .right]
                }
            } else {
                if annotationCenter.x <= listAndSearchOverlayContainerView.frame.maxX {
                    preferredLocations = [.bottom, .right, .left, .top]
                } else {
                    preferredLocations = [.right, .bottom, .top, .left]
                }
            }
        }
    
        let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    
        let popoverDistanceFromAnnotationCenterY = 0.5 * annotationSize.height + spacing
        let totalHeight = popoverDistanceFromAnnotationCenterY + popoverSize.height + spacing
        let top = totalHeight - annotationCenter.y
        let bottom = annotationCenter.y + totalHeight - viewSize.height
        
        let popoverDistanceFromAnnotationCenterX = 0.5 * annotationSize.width + spacing
        let totalWidth = popoverDistanceFromAnnotationCenterX + popoverSize.width + spacing
        let left = totalWidth - annotationCenter.x
        let right = annotationCenter.x + totalWidth - viewSize.width
        
        var x = annotationCenter.x > viewCenter.x ? viewSize.width - popoverSize.width - spacing : spacing
        var y = annotationCenter.y > viewCenter.y ? viewSize.height - popoverSize.height - spacing : spacing

        let canFitTopOrBottom = viewSize.width - annotationCenter.x > 0.5*popoverSize.width && annotationCenter.x > 0.5*popoverSize.width
        let fitsTop = top < 0 && canFitTopOrBottom
        let fitsBottom = bottom < 0 && canFitTopOrBottom
        
        let canFitLeftOrRight = viewSize.height - annotationCenter.y > 0.5*popoverSize.height && annotationCenter.y > 0.5*popoverSize.width
        let fitsLeft = left < 0 && canFitLeftOrRight
        let fitsRight = right < 0 && canFitLeftOrRight
        
        var didFitPreferredLocation = false
        for preferredLocation in preferredLocations {
            didFitPreferredLocation = true
            if preferredLocation == .top && fitsTop {
                x = annotationCenter.x - 0.5 * popoverSize.width
                y = annotationCenter.y - totalHeight
            } else if preferredLocation == .bottom && fitsBottom {
                x = annotationCenter.x - 0.5 * popoverSize.width
                y = annotationCenter.y + popoverDistanceFromAnnotationCenterY
            } else if preferredLocation == .left && fitsLeft {
                x = annotationCenter.x - totalWidth
                y = annotationCenter.y - 0.5 * popoverSize.height
            } else if preferredLocation == .right && fitsRight {
                x = annotationCenter.x + popoverDistanceFromAnnotationCenterX
                y = annotationCenter.y - 0.5 * popoverSize.height
            } else if preferredLocation == .top && top < 0 {
                y = annotationCenter.y - totalHeight
            } else if preferredLocation == .bottom && bottom < 0 {
                y = annotationCenter.y + popoverDistanceFromAnnotationCenterY
            } else if preferredLocation == .left && left < 0 {
                x = annotationCenter.x - totalWidth
            } else if preferredLocation == .right && right < 0 {
                x = annotationCenter.x + popoverDistanceFromAnnotationCenterX
            } else {
                didFitPreferredLocation = false
            }
            
            if didFitPreferredLocation {
                break
            }
        }
        
        if (!didFitPreferredLocation) {
            if (fitsTop || fitsBottom) {
                x = annotationCenter.x - 0.5 * popoverSize.width
                y = annotationCenter.y + (top < bottom ? 0 - totalHeight : popoverDistanceFromAnnotationCenterY)
            } else if (fitsLeft || fitsRight) {
                x = annotationCenter.x + (left < right ? 0 - totalWidth : popoverDistanceFromAnnotationCenterX)
                y = annotationCenter.y - 0.5 * popoverSize.height
            } else if (top < 0) {
                y = annotationCenter.y - totalHeight
            } else if (bottom < 0) {
                y = annotationCenter.y + popoverDistanceFromAnnotationCenterY
            } else if (left < 0) {
                x = annotationCenter.x - totalWidth
            } else if (right < 0) {
                x = annotationCenter.x + popoverDistanceFromAnnotationCenterX
            }
        }
       
        articleVC.view.frame = CGRect(origin: CGPoint(x: x, y: y), size: popoverSize)
    }
    
    // MARK: - Search Filter Dropdown
    
    var isSearchFilterDropDownShowing: Bool = false {
        didSet {
            guard oldValue != isSearchFilterDropDownShowing else {
                return
            }
            
            if isSearchFilterDropDownShowing {
                showSearchFilterDropdown(completion: { (done) in })
            } else {
                hideSearchFilterDropdown(completion: { (done) in })
            }
            
            updateSearchFilterTitle()
        }
    }
    
    fileprivate func showSearchFilterDropdown(completion: @escaping ((Bool) -> Void)) {
        
        guard let isSearchBarInNavigationBar = self.isSearchBarInNavigationBar else {
            // TODO: error
            return
        }
        
        let origHeight = searchFilterListController.preferredHeight(for: view.bounds.size.width)
        
        
        let frame: CGRect
        if (isSearchBarInNavigationBar) {
            frame = CGRect(x: 0,
                           y: extendedNavBarView.frame.minY,
                           width: extendedNavBarView.bounds.width,
                           height: 0)
            
        } else {
            frame = self.view.convert(CGRect(x: 0,
                                             y: listAndSearchOverlayFilterSelectorContainerView.frame.maxY,
                                             width: listAndSearchOverlayFilterSelectorContainerView.bounds.width,
                                             height: 0),
                                      from: listAndSearchOverlayContainerView)
        }
        
        touchOutsideOverlayView.resetInsideRects()
        touchOutsideOverlayView.addInsideRect(fromView: filterDropDownContainerView)
        touchOutsideOverlayView.addInsideRect(fromView: listAndSearchOverlayFilterSelectorContainerView)
        self.view.addSubview(touchOutsideOverlayView)
        
        filterDropDownContainerView.frame = frame
        searchFilterListController.currentFilterType = currentSearchFilter
        self.view.addSubview(filterDropDownContainerView)
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            
            self.filterDropDownContainerView.frame = CGRect(x: self.filterDropDownContainerView.frame.origin.x,
                                                            y: self.filterDropDownContainerView.frame.origin.y,
                                                            width: self.filterDropDownContainerView.frame.size.width,
                                                            height: origHeight)
            
        }, completion: { (done) in
            completion(done)
        })
    }
    
    fileprivate func hideSearchFilterDropdown(completion: @escaping ((Bool) -> Void)) {
        
        let origHeight = searchFilterListController.preferredHeight(for: view.bounds.size.width)
        
        self.touchOutsideOverlayView.removeFromSuperview()
        
        UIView.commitAnimations()
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            
            self.filterDropDownContainerView.frame = CGRect(x: self.filterDropDownContainerView.frame.origin.x,
                                                            y: self.filterDropDownContainerView.frame.origin.y,
                                                            width: self.filterDropDownContainerView.frame.width,
                                                            height: 0)
        }, completion: { (done) in
            self.filterDropDownContainerView.removeFromSuperview()
            self.filterDropDownContainerView.frame.size.height = origHeight
            completion(done)
        })
    }

    
    fileprivate func updateSearchFilterTitle() {
        
        let title: String
        let image: UIImage
        let accessibilityLabel: String
        if (isSearchFilterDropDownShowing) {
            filterDropDownContainerView.accessibilityViewIsModal = true
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, filterDropDownContainerView)
            accessibilityLabel = WMFLocalizedString("places-dismiss-filter-list-accessibility-label", value:"Dismiss search filters", comment:"Accessibility title for the button that dismisses search filters")
            title = WMFLocalizedString("places-filter-list-title", value:"Search filters", comment:"Title shown above list of search filters that can be selected")
            image = UIImage(cgImage: #imageLiteral(resourceName: "chevron-down-large").cgImage!, scale: 1.0, orientation: .down) // `.down` is 180 rotation, yielding a chevron pointing up
        } else {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, searchBar)
            accessibilityLabel = WMFLocalizedString("places-show-filter-list-accessibility-label", value:"Show search filters", comment:"Accessibility title for the button that shows search filters")

            switch currentSearchFilter {
            case .top:
                title = PlaceSearchFilterListController.topArticlesFilterLocalizedTitle
            case .saved:
                title = PlaceSearchFilterListController.savedArticlesFilterLocalizedTitle
            }
            image = #imageLiteral(resourceName: "chevron-down-large")
        }
        
        let attributedTitle: NSMutableAttributedString
        if (viewMode != .search) {
            
            attributedTitle = NSMutableAttributedString(string: title + "  ")  // load-bearing spaces
            let imageAttachment = NSTextAttachment()
            imageAttachment.image = image
            
            let font = filterSelectorView.button.titleLabel?.font ?? UIFont.systemFont(ofSize: 17)
            imageAttachment.setImageHeight(9, font: font)
            let imageString = NSAttributedString(attachment: imageAttachment)
            attributedTitle.append(imageString)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            attributedTitle.addAttribute(NSParagraphStyleAttributeName, value: paragraphStyle, range: NSMakeRange(0, attributedTitle.length))
            attributedTitle.addAttribute(NSForegroundColorAttributeName, value: UIColor.wmf_blue, range: NSMakeRange(0, attributedTitle.length))

        } else {
            attributedTitle = NSMutableAttributedString(string: title)
            attributedTitle.addAttribute(NSForegroundColorAttributeName, value: UIColor.black, range: NSMakeRange(0, attributedTitle.length))
        }
        
        UIView.performWithoutAnimation {
            self.filterSelectorView.button.accessibilityLabel = accessibilityLabel
            self.filterSelectorView.button.setAttributedTitle(attributedTitle, for: .normal)
            self.filterSelectorView.button.layoutIfNeeded()
        }
    }
    
    
    fileprivate func updateSearchBarText(forSearch search: PlaceSearch) {
        if (isDefaultSearch(search)) {
            searchBar?.text = nil
        } else {
            searchBar?.text = search.string ?? search.localizedDescription
        }
        
    }
    
    fileprivate func updateSearchBarText() {
        guard let search = currentSearch else {
            searchBar?.text = nil
            return
        }
        updateSearchBarText(forSearch: search)
    }

    
    @IBAction func toggleSearchFilterDropDown(_ sender: Any) {
        self.isSearchFilterDropDownShowing = !isSearchFilterDropDownShowing
    }
    
    func setupEmptySearchOverlayView() {
        emptySearchOverlayView.mainLabel.text = WMFLocalizedString("places-empty-search-title", value:"Search for Wikipedia articles with geographic locations", comment:"Title text shown on an overlay when there are no recent Places searches. Describes that you can search Wikipedia for articles with geographic locations.")
        emptySearchOverlayView.detailLabel.text = WMFLocalizedString("places-empty-search-description", value:"Explore cities, countries, continents, natural landmarks, historical events, buildings and more.", comment:"Detail text shown on an overlay when there are no recent Places searches. Describes the kind of articles you can search for.")
    }
    
    // MARK: - Search Suggestions & Completions
    
    var currentSearchString: String {
        guard let currentSearchString = searchBar?.text?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines) else {
            return ""
        }
        return currentSearchString
    }
    
    func updateSearchSuggestions(withCompletions completions: [PlaceSearch], isSearchDone: Bool) {
        guard currentSearchString != "" || completions.count > 0 else {
            
            // Search is empty, run a default search
            
            var defaultSuggestions = [PlaceSearch]()
            
            let yourLocationSuggestionTitle = WMFLocalizedString("places-search-your-current-location", value:"Your current location", comment:"A search suggestion for showing articles near your current location.")
            defaultSuggestions.append(PlaceSearch(filter: currentSearchFilter, type: .nearby, origin: .user, sortStyle: .links, string: nil, region: nil, localizedDescription: yourLocationSuggestionTitle, searchResult: nil))
            
            switch (currentSearchFilter) {
            case .top:
                defaultSuggestions.append(PlaceSearch(filter: .top, type: .location, origin: .system, sortStyle: .links, string: nil, region: nil, localizedDescription: WMFLocalizedString("places-search-top-articles", value:"All top articles", comment:"A search suggestion for top articles"), searchResult: nil))
            case .saved:
                defaultSuggestions.append(PlaceSearch(filter: .saved, type: .location, origin: .system, sortStyle: .links, string: nil, region: nil, localizedDescription: WMFLocalizedString("places-search-saved-articles", value:"All saved articles", comment:"A search suggestion for saved articles"), searchResult: nil))
            }

            var recentSearches: [PlaceSearch] = []
            do {
                let moc = dataStore.viewContext
                let request = WMFKeyValue.fetchRequest()
                request.predicate = NSPredicate(format: "group == %@", currentSearchHistoryGroup())
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                let results = try moc.fetch(request)
                let count = results.count
                if count > searchHistoryCountLimit {
                    for result in results[searchHistoryCountLimit..<count] {
                        moc.delete(result)
                    }
                }
                let limit = min(count, searchHistoryCountLimit)
                recentSearches = try results[0..<limit].map({ (kv) -> PlaceSearch in
                    guard let ps = PlaceSearch(object: kv.value) else {
                            throw PlaceSearchError.deserialization(object: kv.value)
                    }
                    return ps
                })
            } catch let error {
                DDLogError("Error fetching recent place searches: \(error)")
            }
            searchSuggestionController.siteURL = siteURL
            searchSuggestionController.searches = [defaultSuggestions, recentSearches, [], []]
            
            if (recentSearches.count == 0) {
                setupEmptySearchOverlayView()
                emptySearchOverlayView.frame = searchSuggestionView.frame
                searchSuggestionView.superview?.addSubview(emptySearchOverlayView)
            } else {
                emptySearchOverlayView.removeFromSuperview()
            }

            return
        }
        
        emptySearchOverlayView.removeFromSuperview()
        
        guard currentSearchString != "" else {
            searchSuggestionController.searches = [[], [], [], completions]
            return
        }

        let currentSearchScopeName: String
        switch (currentSearchFilter) {
        case .top:
            currentSearchScopeName = WMFLocalizedString("places-search-top-articles-that-match-scope", value: "Nearby", comment: "Title used in search description when searching an area for Top articles")
        case .saved:
            currentSearchScopeName = PlaceSearchFilterListController.savedArticlesFilterLocalizedTitle
        }

        var currentSearchStringSuggestions = [PlaceSearch]()
        if isSearchDone {
            let currentSearchStringTitle = String.localizedStringWithFormat(WMFLocalizedString("places-search-articles-that-match", value:"%1$@ matching “%2$@”", comment:"A search suggestion for filtering the articles in the area by the search string. %1$@ is replaced by the a string depending on the current filter ('Nearby' for 'Top Articles' or 'Saved articles'). %2$@ is replaced with the search string"), currentSearchScopeName, currentSearchString)
            currentSearchStringSuggestions.append(PlaceSearch(filter: currentSearchFilter, type: .text, origin: .user, sortStyle: .links, string: currentSearchString, region: nil, localizedDescription: currentSearchStringTitle, searchResult: nil))
        }
        
        searchSuggestionController.searches = [[], [], currentSearchStringSuggestions, completions]
    }
    
    func handleCompletion(searchResults: [MWKSearchResult], siteURL: URL) -> [PlaceSearch] {
        var set = Set<String>()
        let completions = searchResults.flatMap { (result) -> PlaceSearch? in
            guard let location = result.location,
                let dimension = result.geoDimension?.doubleValue,
                let title = result.displayTitle,
                let url = (self.siteURL as NSURL).wmf_URL(withTitle: title),
                let key = (url as NSURL).wmf_articleDatabaseKey,
                !set.contains(key) else {
                    return nil
            }
            set.insert(key)
            let region = [location.coordinate].wmf_boundingRegion(with: dimension)
            return PlaceSearch(filter: currentSearchFilter, type: .location, origin: .user, sortStyle: .links, string: nil, region: region, localizedDescription: result.displayTitle, searchResult: result, siteURL: siteURL)
        }
        updateSearchSuggestions(withCompletions: completions, isSearchDone: true)
        return completions
    }
    
    public func showNearbyArticles() {
        guard let _ = view else { // force view instantiation
            return
        }
        
        guard currentSearch != nil else { // if current search is nil, this is the initial setup for the view and it will recenter automatically
            return
        }
        
        currentSearch = nil // will cause the default search to perform after re-centering
        recenterOnUserLocation(self)
    }
    
    public func showArticleURL(_ articleURL: URL) {
        guard let article = dataStore.fetchArticle(with: articleURL), let title = (articleURL as NSURL).wmf_title,
            let _ = view else { // force view instantiation
            return
        }
        let region = self.region(thatFits: [article])
        let searchResult = MWKSearchResult(articleID: 0, revID: 0, displayTitle: title, wikidataDescription: article.wikidataDescription, extract: article.snippet, thumbnailURL: article.thumbnailURL, index: nil, isDisambiguation: false, isList: false, titleNamespace: nil)
        currentSearch = PlaceSearch(filter: .top, type: .location, origin: .user, sortStyle: .links, string: nil, region: region, localizedDescription: title, searchResult: searchResult, siteURL: (articleURL as NSURL).wmf_site)
    }
    
    fileprivate func searchForFirstSearchSuggestion() {
        if searchSuggestionController.searches[PlaceSearchSuggestionController.completionSection].count > 0 {
            currentSearch = searchSuggestionController.searches[PlaceSearchSuggestionController.completionSection][0]
        } else if searchSuggestionController.searches[PlaceSearchSuggestionController.currentStringSection].count > 0 {
            currentSearch = searchSuggestionController.searches[PlaceSearchSuggestionController.currentStringSection][0]
        }
    }
    
    fileprivate var isWaitingForSearchSuggestionUpdate = false {
        didSet {
            if (oldValue == false && isWaitingForSearchSuggestionUpdate == true) {
                // start progress bar
                isProgressHidden = false
                progressView.setProgress(0, animated: false)
                perform(#selector(incrementProgress), with: nil, afterDelay: 0.3)
            } else if (isWaitingForSearchSuggestionUpdate == false) {
                // stop progress bar
                self.progressView.setProgress(1.0, animated: true)
                self.isProgressHidden = true
            }
        }
    }
    
    func updateSearchCompletionsFromSearchBarText() {
        switch (currentSearchFilter) {
        case .top:
            updateSearchCompletionsFromSearchBarTextForTopArticles()
        case .saved:
            // TODO: add suggestions here?
            self.isWaitingForSearchSuggestionUpdate = false
        }
    }
    
    func updateSearchCompletionsFromSearchBarTextForTopArticles()
    {
        guard let text = searchBar?.text?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines), text != "" else {
            updateSearchSuggestions(withCompletions: [], isSearchDone: false)
            self.isWaitingForSearchSuggestionUpdate = false
            return
        }
        let siteURL = self.siteURL
        searchFetcher.fetchArticles(forSearchTerm: text, siteURL: siteURL, resultLimit: 24, failure: { (error) in
            guard text == self.searchBar?.text else {
                return
            }
            self.updateSearchSuggestions(withCompletions: [], isSearchDone: false)
            self.isWaitingForSearchSuggestionUpdate = false
        }) { (searchResult) in
            guard text == self.searchBar?.text else {
                return
            }
            
            if let suggestion = searchResult.searchSuggestion {
                DDLogDebug("got suggestion! \(suggestion)")
            }
            
            let completions = self.handleCompletion(searchResults: searchResult.results ?? [], siteURL: siteURL)
            self.isWaitingForSearchSuggestionUpdate = false
            guard completions.count < 10 else {
                return
            }
            
            let center = self.mapView.userLocation.coordinate
            let region = CLCircularRegion(center: center, radius: 40075000, identifier: "world")
            self.locationSearchFetcher.fetchArticles(withSiteURL: self.siteURL, in: region, matchingSearchTerm: text, sortStyle: .links, resultLimit: 24, completion: { (locationSearchResults) in
                guard text == self.searchBar?.text else {
                    return
                }
                var combinedResults: [MWKSearchResult] = searchResult.results ?? []
                let newResults = locationSearchResults.results as [MWKSearchResult]
                combinedResults.append(contentsOf: newResults)
                let _ = self.handleCompletion(searchResults: combinedResults, siteURL: siteURL)
            }) { (error) in
                guard text == self.searchBar?.text else {
                    return
                }
            }
        }
    }
    
    @IBAction func closeSearch(_ sender: Any) {
        searchBar?.endEditing(true)
        currentSearch = nil
        performDefaultSearchIfNecessary(withRegion: nil)
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, view)
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        viewMode = .search
        deselectAllAnnotations()
        
        // Only update suggestion on *begin* editing if there is no text
        // Otherwise, it just clears perfectly good results
        if currentSearchString == "" {
            updateSearchSuggestions(withCompletions: [], isSearchDone: false)
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        isWaitingForSearchSuggestionUpdate = true
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(updateSearchCompletionsFromSearchBarText), with: nil, afterDelay: 0.2)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        
        guard let searchText = searchBar.text else {
            assertionFailure("could not read search text")
            return
        }
        
        guard searchText.trimmingCharacters(in: .whitespaces).characters.count > 0 else {
            return
        }
        
        guard !isWaitingForSearchSuggestionUpdate else {
            return
        }
        
        searchBar.endEditing(true)
        searchForFirstSearchSuggestion()
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        updateViewModeFromSegmentedControl()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return articleFetchedResultsController.sections?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return articleFetchedResultsController.sections?[section].numberOfObjects ?? 0
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard viewMode == .list else {
            return
        }
        logListViewImpression(forIndexPath: indexPath)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: WMFNearbyArticleTableViewCell.identifier(), for: indexPath) as? WMFNearbyArticleTableViewCell else {
            return UITableViewCell()
        }
        
        let article = articleFetchedResultsController.object(at: indexPath)
        
        cell.titleText = article.displayTitle
        cell.descriptionText = article.capitalizedWikidataDescriptionOrSnippet
        cell.setImageURL(article.thumbnailURL)
        cell.articleLocation = article.location
        
        var userLocation: CLLocation?
        var userHeading: CLHeading?
        
        if locationManager.isUpdating {
            userLocation = locationManager.location
            userHeading = locationManager.heading
        }
        cell.update(userLocation: userLocation, heading: userHeading)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let article = articleFetchedResultsController.object(at: indexPath)
        let title = article.savedDate == nil ? WMFLocalizedString("action-save", value:"Save", comment:"Title for the 'Save' action\n{{Identical|Save}}") : WMFLocalizedString("action-saved", value:"Saved", comment:"Title for the 'Unsave' action - Indicates the article is saved\n{{Identical|Saved}}")
        let saveForLaterAction = UITableViewRowAction(style: .default, title: title) { (action, indexPath) in
            CATransaction.begin()
            CATransaction.setCompletionBlock({
                let article = self.articleFetchedResultsController.object(at: indexPath)
                self.perform(action: .save, onArticle: article)
            })
            tableView.setEditing(false, animated: true)
            CATransaction.commit()
        }
        saveForLaterAction.backgroundColor = .wmf_darkBlue
        
        let shareAction = UITableViewRowAction(style: .default, title: WMFLocalizedString("action-share", value:"Share", comment:"Title for the 'Share' action\n{{Identical|Share}}")) { (action, indexPath) in
            tableView.setEditing(false, animated: true)
            let article = self.articleFetchedResultsController.object(at: indexPath)
            self.perform(action: .share, onArticle: article)
        }
        shareAction.backgroundColor = .wmf_blue
        return [saveForLaterAction, shareAction]
    }
    
    func logListViewImpression(forIndexPath indexPath: IndexPath) {
        let article = articleFetchedResultsController.object(at: indexPath)
        tracker?.wmf_logActionImpression(inContext: listTrackerContext, contentType: article)
    }
    
    func logListViewImpressionsForVisibleCells() {
        for indexPath in listView.indexPathsForVisibleRows ?? [] {
            logListViewImpression(forIndexPath: indexPath)
        }
    }
    
    func updateDistanceFromUserOnVisibleCells() {
        guard !listView.isHidden else {
            return
        }
        let heading = locationManager.heading
        let location = locationManager.location
        for cell in listView.visibleCells {
            guard let locationCell = cell as? WMFNearbyArticleTableViewCell else {
                continue
            }
            locationCell.update(userLocation: location, heading: heading)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let article = articleFetchedResultsController.object(at: indexPath)
        perform(action: .read, onArticle: article)
    }
    
    // MARK: - PlaceSearchSuggestionControllerDelegate
    
    func placeSearchSuggestionController(_ controller: PlaceSearchSuggestionController, didSelectSearch search: PlaceSearch) {
        searchBar?.endEditing(true)
        currentSearch = search
    }
    
    func placeSearchSuggestionControllerClearButtonPressed(_ controller: PlaceSearchSuggestionController) {
        clearSearchHistory()
        updateSearchSuggestions(withCompletions: [], isSearchDone: false)
    }
    
    func placeSearchSuggestionController(_ controller: PlaceSearchSuggestionController, didDeleteSearch search: PlaceSearch) {
        let moc = dataStore.viewContext
        guard let kv = keyValue(forPlaceSearch: search, inManagedObjectContext: moc) else {
            return
        }
        moc.delete(kv)
        do {
            try moc.save()
        } catch let error {
            DDLogError("Error removing kv: \(error.localizedDescription)")
        }
        updateSearchSuggestions(withCompletions: [], isSearchDone: false)
    }
    
    // MARK: - WMFLocationManagerDelegate
    
    func updateUserLocationAnnotationViewHeading(_ heading: CLHeading) {
        guard let view = mapView.view(for: mapView.userLocation) as? UserLocationAnnotationView else {
            return
        }
        view.isHeadingArrowVisible = heading.headingAccuracy > 0 && heading.headingAccuracy < 90
        view.heading = heading.trueHeading
    }
    
    func zoomAndPanMapView(toLocation location: CLLocation) {
        let region = [location.coordinate].wmf_boundingRegion(with: 10000)
        mapRegion = region
        if let searchRegion = currentSearchRegion, isDistanceSignificant(betweenRegion: searchRegion, andRegion: region) {
            performDefaultSearch(withRegion: mapRegion)
        } else {
            performDefaultSearchIfNecessary(withRegion: region)
        }
    }
    
    var panMapToNextLocationUpdate = true
    
    func locationManager(_ controller: WMFLocationManager, didUpdate location: CLLocation) {
        updateDistanceFromUserOnVisibleCells()
        guard panMapToNextLocationUpdate else {
            return
        }
        panMapToNextLocationUpdate = false
        zoomAndPanMapView(toLocation: location)
    }
    
    func locationManager(_ controller: WMFLocationManager, didReceiveError error: Error) {
    }
    
    func locationManager(_ controller: WMFLocationManager, didUpdate heading: CLHeading) {
        updateUserLocationAnnotationViewHeading(heading)
        updateDistanceFromUserOnVisibleCells()
    }
    
    func locationManager(_ controller: WMFLocationManager, didChangeEnabledState enabled: Bool) {
        if enabled {
            panMapToNextLocationUpdate = currentSearch == nil
            locationManager.startMonitoringLocation()
        } else {
            panMapToNextLocationUpdate = false
            locationManager.stopMonitoringLocation()
            performDefaultSearchIfNecessary(withRegion: nil)
        }
    }
    
    @IBAction fileprivate func recenterOnUserLocation(_ sender: Any) {
        guard WMFLocationManager.isAuthorized() else {
            promptForLocationAccess()
            return
        }
        zoomAndPanMapView(toLocation: locationManager.location)
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updatePlaces()
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController, willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>, in view: AutoreleasingUnsafeMutablePointer<UIView>) {
        let oldRect = rect.pointee
        let center = CGPoint(x: view.pointee.bounds.midX, y: view.pointee.bounds.midY)
        let newOrigin = CGPoint(x: center.x - 0.5*oldRect.width, y: center.y - 0.5*oldRect.height)
        rect.pointee = CGRect(origin: newOrigin, size: oldRect.size)
    }
    
    
    // MARK: - EnableLocationViewControllerDelegate
    
    func enableLocationViewController(_ enableLocationViewController: EnableLocationViewController, didFinishWithShouldPromptForLocationAccess shouldPromptForLocationAccess: Bool) {
        guard shouldPromptForLocationAccess else {
            performDefaultSearchIfNecessary(withRegion: nil)
            return
        }
        guard WMFLocationManager.isAuthorizationNotDetermined() else {
            UIApplication.shared.wmf_openAppSpecificSystemSettings()
            return
        }
        locationManager.startMonitoringLocation()
    }
    
    // MARK: - ArticlePlaceViewDelegate
    
    func articlePlaceViewWasTapped(_ articlePlaceView: ArticlePlaceView) {
        guard let article = selectedArticlePopover?.article else {
            return
        }
        perform(action: .read, onArticle: article)
    }
    
    // MARK: - WMFAnalyticsViewNameProviding
    
    public var analyticsName: String {
        return "Places"
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === overlaySliderPanGestureRecognizer else {
            return false
        }
        
        let location = touch.location(in: view)
        let shouldReceive = location.x < listAndSearchOverlayContainerView.frame.maxX && abs(location.y - listAndSearchOverlayContainerView.frame.maxY - 10) < 32
        return shouldReceive
    }
    
    // MARK: - TouchOutsideOverlayDelegate
    
    func touchOutside(_ overlayView: TouchOutsideOverlayView) {
        toggleSearchFilterDropDown(overlayView)
    }
    
    // MARK: - PlaceSearchFilterListDelegate
    
    func placeSearchFilterListController(_ placeSearchFilterListController: PlaceSearchFilterListController, countForFilterType: PlaceFilterType) -> Int {
        switch (countForFilterType) {
        case .top:
            return displayCountForTopPlaces
        case .saved:
            do {
                let moc = dataStore.viewContext
                return try moc.count(for: placeSearchService.fetchRequestForSavedArticlesWithLocation)
            } catch let error {
                DDLogError("Error fetching saved article count: \(error)")
                return 0
                
            }
        }
    }
    
    func placeSearchFilterListController(_ placeSearchFilterListController: PlaceSearchFilterListController,
                                          didSelectFilterType filterType: PlaceFilterType) {
        currentSearchFilter = filterType
        isSearchFilterDropDownShowing = false
    }
}

extension PlacesViewController {
    func regionWillChange() {
        deselectAllAnnotations()
        isMovingToRegion = true
    }
    
    func regionDidChange() {
        _mapRegion = mapView.region
        guard performDefaultSearchOnNextMapRegionUpdate == false else {
            performDefaultSearchOnNextMapRegionUpdate = false
            performDefaultSearchIfNecessary(withRegion: nil)
            return
        }
        regroupArticlesIfNecessary(forVisibleRegion: mapView.region)
        
        updateViewIfMapMovedSignificantly(forVisibleRegion: mapView.region)
        
        isMovingToRegion = false
        
        selectVisibleKeyToSelectIfNecessary()
        
        updateShouldShowAllImagesIfNecessary()
    }
    
    func didSelect(place: ArticlePlace, annotationView: MapAnnotationView) {
        previouslySelectedArticlePlaceIdentifier = place.identifier
        
        guard place.articles.count == 1 else {
            deselectAllAnnotations()
            
            var minDistance = CLLocationDistanceMax
            let center = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            for article in place.articles {
                guard let location = article.location else {
                    continue
                }
                let distance = location.distance(from: center)
                if distance < minDistance {
                    minDistance = distance
                    articleKeyToSelect = article.key
                }
            }
            mapRegion = region(thatFits: place.articles)
            return
        }
        
        showPopover(forAnnotationView: annotationView)
    }
    
    func didDeselectAnnotation() {
        selectedArticleKey = nil
        dismissCurrentArticlePopover()
    }
    
    func viewFor(place: ArticlePlace) -> MapAnnotationView? {
        let reuseIdentifier = "org.wikimedia.articlePlaceView"
        var placeView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as! ArticlePlaceView?
        
        if placeView == nil {
            #if OSM
                placeView = ArticlePlaceView(reuseIdentifier: reuseIdentifier)
            #else
                placeView = ArticlePlaceView(annotation: place, reuseIdentifier: reuseIdentifier)
            #endif
        } else {
            placeView?.prepareForReuse()
            placeView?.annotation = place
        }
        
        placeView?.delegate = self
        
        if showingAllImages {
            placeView?.set(alwaysShowImage: true, animated: false)
        }
        
        if place.articles.count > 1 && place.nextCoordinate == nil {
            placeView?.alpha = 0
            placeView?.transform = CGAffineTransform(scaleX: animationScale, y: animationScale)
            dispatchOnMainQueue({
                self.countOfAnimatingAnnotations += 1
                UIView.animate(withDuration: self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.transform = CGAffineTransform.identity
                    placeView?.alpha = 1
                }, completion: { (done) in
                    self.countOfAnimatingAnnotations -= 1
                })
            })
        } else if let nextCoordinate = place.nextCoordinate {
            placeView?.alpha = 0
            dispatchOnMainQueue({
                self.countOfAnimatingAnnotations += 1
                UIView.animate(withDuration: 2*self.animationDuration, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .allowUserInteraction, animations: {
                    place.coordinate = nextCoordinate
                }, completion: { (done) in
                    self.countOfAnimatingAnnotations -= 1
                })
                UIView.animate(withDuration: 0.5*self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.alpha = 1
                }, completion: nil)
            })
        } else {
            placeView?.alpha = 0
            dispatchOnMainQueue({
                self.countOfAnimatingAnnotations += 1
                UIView.animate(withDuration: self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.alpha = 1
                }, completion: { (done) in
                    self.countOfAnimatingAnnotations -= 1
                })
            })
        }
        
        return placeView
    }
}

#if OSM
    
// MARK: - MGLMapViewDelegate
extension PlacesViewController: MGLMapViewDelegate {
    func mapView(_ mapView: MGLMapView, regionWillChangeAnimated animated: Bool) {
        regionWillChange()
    }
    
    func mapView(_ mapView: MGLMapView, regionDidChangeAnimated animated: Bool) {
        regionDidChange()
    }
    
    func mapView(_ mapView: MGLMapView, didSelect annotationView: MGLAnnotationView) {
        guard let place = annotationView.annotation as? ArticlePlace, let annotationView = annotationView as? MapAnnotationView else {
            return
        }
        didSelect(place: place, annotationView: annotationView)
    }
    
    func mapView(_ mapView: MGLMapView, didDeselect view: MGLAnnotationView) {
        didDeselectAnnotation()
    }
    
    func mapView(_ mapView: MGLMapView, viewFor annotation: MGLAnnotation) -> MGLAnnotationView? {
        guard let place = annotation as? ArticlePlace else {
            return nil
        }
        
        return viewFor(place: place)
    }
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        
    }
}
#else
    
// MARK: - MKMapViewDelegate
extension PlacesViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        regionWillChange()
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        regionDidChange()
    }
    
    func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
        guard let place = annotationView.annotation as? ArticlePlace, let annotationView = annotationView as? MapAnnotationView else {
            return
        }
        
        didSelect(place: place, annotationView: annotationView)
    }
    
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        didDeselectAnnotation()
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let place = annotation as? ArticlePlace else {
            // CRASH WORKAROUND
            // The UIPopoverController that the map view presents from the default user location annotation is causing a crash. Using our own annotation view for the user location works around this issue.
            if let userLocation = annotation as? MKUserLocation {
                let userViewReuseIdentifier = "org.wikimedia.userLocationAnnotationView"
                let placeView = mapView.dequeueReusableAnnotationView(withIdentifier: userViewReuseIdentifier) as? UserLocationAnnotationView ?? UserLocationAnnotationView(annotation: userLocation, reuseIdentifier: userViewReuseIdentifier)
                placeView.annotation = userLocation
                return placeView
            }
            return nil
        }
        
        return viewFor(place: place)
    }
}
    
#endif

// MARK: -

class PlaceSearchFilterSelectorView: UIView {
    
    @IBOutlet weak var button: UIButton!
}

// MARK: -

class PlaceSearchEmptySearchOverlayView: UIView {
    
    @IBOutlet weak var mainLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    
}

// MARK: - UIViewControllerPreviewingDelegate
extension PlacesViewController {
    override func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard viewMode == .list else {
            return nil
        }
        let point = view.convert(location, to: listView)
        guard
            let indexPath = listView.indexPathForRow(at: point),
            let url = self.articleFetchedResultsController.object(at: indexPath).url,
            let cell = listView.cellForRow(at: indexPath)
        else {
            return nil
        }
        previewingContext.sourceRect = cell.convert(cell.bounds, to: view)
        return WMFArticleViewController(articleURL: url, dataStore: dataStore)
    }
    
    override func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        wmf_push(viewControllerToCommit, animated: true)
    }
}
