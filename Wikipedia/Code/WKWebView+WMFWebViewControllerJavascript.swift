
import Foundation

enum WMFArticleFooterMenuItem2: String {

    // Reminder: These are the strings used by the footerMenu JS transform:
    case languages, lastEdited, pageIssues, disambiguation, coordinate
    
    private var footerMenuJSTransformEnumString: String {
        return self.rawValue
    }
    
    private var footerMenuTransformJSEnumPath: String {
        return "window.wmf.footerMenu.IconTypeEnum.\(footerMenuJSTransformEnumString)"
    }
    
    private var localizedTitleKey: String {
        switch self {
        case .languages: return "page-read-in-other-languages"
        case .lastEdited: return "page-last-edited"
        case .pageIssues: return "page-issues"
        case .disambiguation: return "page-similar-titles"
        case .coordinate: return "page-location"
        }
    }
    
    private func titleSubstitutionStringForArticle(article: MWKArticle) -> String? {
        switch self {
        case .languages:
            return "\(article.languagecount)"
        case .lastEdited:
            let lastModified = article.lastmodified ?? Date()
            let days = NSCalendar.wmf_gregorian().wmf_days(from: lastModified, to: Date())
            return "\(days)"
        default:
            return nil
        }
    }
    
    private var localizedSubtitleKey: String? {
        switch self {
        case .lastEdited: return "page-edit-history"
        default:
            return nil
        }
    }
    
    public func shouldAddItem(with article: MWKArticle) -> Bool {
        switch self {
        case .languages where !article.hasMultipleLanguages:
            return false
        case .pageIssues:
            guard let issues = article.pageIssues(), issues.count > 0 else {
                return false
            }
        case .disambiguation:
            guard let issues = article.disambiguationURLs(), issues.count > 0 else {
                return false
            }
        case .coordinate where !CLLocationCoordinate2DIsValid(article.coordinate):
            return false
        default:
            break
        }
        return true
    }
    
    public func itemAdditionJavascriptString(with article: MWKArticle) -> String {
        var title = article.apostropheEscapedArticleLanguageLocalizedStringForKey(self.localizedTitleKey)
        if let substitutionString = titleSubstitutionStringForArticle(article: article) {
            title = title.replacingOccurrences(of: "$1", with: substitutionString)
        }
        
        var subtitle = ""
        if let subtitleKey = self.localizedSubtitleKey{
            subtitle = article.apostropheEscapedArticleLanguageLocalizedStringForKey(subtitleKey)
        }
        
        let itemSelectionHandler =
            "function(){" +
                "console.log('\(footerMenuJSTransformEnumString)');" +
                "window.webkit.messageHandlers.footerMenuItemClicked.postMessage('\(footerMenuJSTransformEnumString)');" +
        "}"
        
        return "window.wmf.footerMenu.addItem('\(title)', '\(subtitle)', \(self.footerMenuTransformJSEnumPath), \(itemSelectionHandler));"
    }
}

extension WKWebView {
    
    public func wmf_addFooterMenuForArticle(_ article: MWKArticle){
        let header = article.apostropheEscapedArticleLanguageLocalizedStringForKey("article-about-title")

        let itemsJS = [
            WMFArticleFooterMenuItem2.languages,
            WMFArticleFooterMenuItem2.coordinate,
            WMFArticleFooterMenuItem2.lastEdited,
            WMFArticleFooterMenuItem2.pageIssues,
            WMFArticleFooterMenuItem2.disambiguation
            ].filter{$0.shouldAddItem(with: article)}
             .map{$0.itemAdditionJavascriptString(with: article)}
        
        evaluateJavaScript("window.wmf.footerMenu.setHeading( '\(header)' ); \(itemsJS.joined(separator: ""))", completionHandler: nil)
    }
    
}
