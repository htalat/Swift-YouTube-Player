//
//  VideoPlayerView.swift
//  YouTubePlayer
//
//  Created by Giles Van Gruisen on 12/21/14.
//  Copyright (c) 2014 Giles Van Gruisen. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import WebKit

public enum YouTubePlayerState: String {
    case Unstarted = "-1"
    case Ended = "0"
    case Playing = "1"
    case Paused = "2"
    case Buffering = "3"
    case Queued = "4"
}

public enum YouTubePlayerEvents: String {
    case YouTubeIframeAPIReady = "onYouTubeIframeAPIReady"
    case Ready = "onReady"
    case StateChange = "onStateChange"
    case PlaybackQualityChange = "onPlaybackQualityChange"
    case PlayerCurrentTime = "onCurrentTime"
}

public enum YouTubePlaybackQuality: String {
    case Small = "small"
    case Medium = "medium"
    case Large = "large"
    case HD720 = "hd720"
    case HD1080 = "hd1080"
    case HighResolution = "highres"
}

public protocol YouTubePlayerDelegate: class {
    func playerReady(_ videoPlayer: YouTubePlayerView)
    func playerStateChanged(_ videoPlayer: YouTubePlayerView, playerState: YouTubePlayerState)
    func playerQualityChanged(_ videoPlayer: YouTubePlayerView, playbackQuality: YouTubePlaybackQuality)
    func playerCurrentTime(_ videoPlayer: YouTubePlayerView, currentTime: Double)
    
}

// Make delegate methods optional by providing default implementations
public extension YouTubePlayerDelegate {

    func playerReady(_ videoPlayer: YouTubePlayerView) {}
    func playerStateChanged(_ videoPlayer: YouTubePlayerView, playerState: YouTubePlayerState) {}
    func playerQualityChanged(_ videoPlayer: YouTubePlayerView, playbackQuality: YouTubePlaybackQuality) {}
    func playerCurrentTime(_ videoPlayer: YouTubePlayerView, currentTime: Double) {}

}

private extension URL {
    func queryStringComponents() -> [String: AnyObject] {

        var dict = [String: AnyObject]()

        // Check for query string
        if let query = self.query {

            // Loop through pairings (separated by &)
            for pair in query.components(separatedBy: "&") {

                // Pull key, val from from pair parts (separated by =) and set dict[key] = value
                let components = pair.components(separatedBy: "=")
                if (components.count > 1) {
                    dict[components[0]] = components[1] as AnyObject?
                }
            }

        }

        return dict
    }
}

public func videoIDFromYouTubeURL(_ videoURL: URL) -> String? {
    if videoURL.pathComponents.count > 1 && (videoURL.host?.hasSuffix("youtu.be"))! {
        return videoURL.pathComponents[1]
    } else if videoURL.pathComponents.contains("embed") {
        return videoURL.pathComponents.last
    }
    return videoURL.queryStringComponents()["v"] as? String
}

/** Embed and control YouTube videos */
open class YouTubePlayerView: UIView, WKNavigationDelegate {

    public typealias YouTubePlayerParameters = [String: AnyObject]
    public var baseURL = "about:blank"

    fileprivate var webView: WKWebView!

    /** The readiness of the player */
    fileprivate(set) open var ready = false

    /** The current state of the video player */
    fileprivate(set) open var playerState = YouTubePlayerState.Unstarted

    /** The current playback quality of the video player */
    fileprivate(set) open var playbackQuality = YouTubePlaybackQuality.Small

    /** Used to configure the player */
    open var playerVars = YouTubePlayerParameters()

    /** Used to respond to player events */
    open weak var delegate: YouTubePlayerDelegate?

    fileprivate(set) open var currentTime: Double = 0.0


    // MARK: Various methods for initialization

    override public init(frame: CGRect) {
        super.init(frame: frame)
        buildWebView(playerParameters())
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        buildWebView(playerParameters())
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        // Remove web view in case it's within view hierarchy, reset frame, add as subview
        webView.removeFromSuperview()
        webView.frame = bounds
        addSubview(webView)
    }


    // MARK: Web view initialization

    fileprivate func buildWebView(_ parameters: [String: AnyObject]) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaPlaybackRequiresUserAction = false
        configuration.preferences.javaScriptEnabled = true

        webView = WKWebView(frame: frame, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
    }


    // MARK: Load player

    open func loadVideoURL(_ videoURL: URL) {
        if let videoID = videoIDFromYouTubeURL(videoURL) {
            loadVideoID(videoID)
        }
    }

    open func loadVideoID(_ videoID: String) {
        var playerParams = playerParameters()
        playerParams["videoId"] = videoID as AnyObject?

        loadWebViewWithParameters(playerParams)
    }

    open func loadPlaylistID(_ playlistID: String) {
        // No videoId necessary when listType = playlist, list = [playlist Id]
        playerVars["listType"] = "playlist" as AnyObject?
        playerVars["list"] = playlistID as AnyObject?

        loadWebViewWithParameters(playerParameters())
    }


    // MARK: Player controls

    open func mute() {
        evaluatePlayerCommand("mute()")
    }

    open func unMute() {
        evaluatePlayerCommand("unMute()")
    }

    open func play() {
        evaluatePlayerCommand("playVideo()")
    }

    open func pause() {
        evaluatePlayerCommand("pauseVideo()")
    }

    open func stop() {
        evaluatePlayerCommand("stopVideo()")
    }

    open func clear() {
        evaluatePlayerCommand("clearVideo()")
    }

    open func seekTo(_ seconds: Float, seekAhead: Bool) {
        evaluatePlayerCommand("seekTo(\(seconds), \(seekAhead))")
    }

    open func getDuration(completion: ((Double?) -> Void)? = nil) {
        evaluatePlayerCommand("getDuration()") { (result) in
            completion?(result as? Double)
        }
    }

    open func getCurrentTime(completion: ((Double?) -> Void)? = nil) {
        evaluatePlayerCommand("getCurrentTime()") { (result) in
            completion?(result as? Double)
        }
    }

    // MARK: Playlist controls

    open func previousVideo() {
        evaluatePlayerCommand("previousVideo()")
    }

    open func nextVideo() {
        evaluatePlayerCommand("nextVideo()")
    }

    fileprivate func evaluatePlayerCommand(_ command: String, completion: ((Any?) -> Void)? = nil) {
        let fullCommand = "player." + command + ";"
        webView.evaluateJavaScript(fullCommand) { (result, error) in
            if let error = error, (error as NSError).code != 5 { // NOTE: ignore :Void return
                print(error)
                printLog("Error executing javascript")
                completion?(nil)
            }

            completion?(result)
        }
    }


    // MARK: Player setup

    fileprivate func loadWebViewWithParameters(_ parameters: YouTubePlayerParameters) {

        // Get HTML from player file in bundle
        let rawHTMLString = htmlStringWithFilePath(playerHTMLPath())!

        // Get JSON serialized parameters string
        let jsonParameters = serializedJSON(parameters as AnyObject)!

        // Replace %@ in rawHTMLString with jsonParameters string
        let htmlString = rawHTMLString.replacingOccurrences(of: "%@", with: jsonParameters)

        // Load HTML in web view
        webView.loadHTMLString(htmlString, baseURL: URL(string: baseURL))
    }

    fileprivate func playerHTMLPath() -> String {
//        return Bundle(for: YouTubePlayerView.self).path(forResource: "YTPlayer", ofType: "html")!
        return Bundle.module.path(forResource: "YTPlayer", ofType: "html")!
    }

    fileprivate func htmlStringWithFilePath(_ path: String) -> String? {

        do {

            // Get HTML string from path
            let htmlString = try NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue)

            return htmlString as String

        } catch _ {

            // Error fetching HTML
            printLog("Lookup error: no HTML file found for path")

            return nil
        }
    }


    // MARK: Player parameters and defaults

    fileprivate func playerParameters() -> YouTubePlayerParameters {

        return [
            "height": "100%" as AnyObject,
            "width": "100%" as AnyObject,
            "events": playerCallbacks() as AnyObject,
            "playerVars": playerVars as AnyObject
        ]
    }

    fileprivate func playerCallbacks() -> YouTubePlayerParameters {
        return [
            "onReady": "onReady" as AnyObject,
            "onStateChange": "onStateChange" as AnyObject,
            "onPlaybackQualityChange": "onPlaybackQualityChange" as AnyObject,
            "onError": "onPlayerError" as AnyObject
        ]
    }

    fileprivate func serializedJSON(_ object: AnyObject) -> String? {

        do {
            // Serialize to JSON string
            let jsonData = try JSONSerialization.data(withJSONObject: object, options: JSONSerialization.WritingOptions.prettyPrinted)

            // Succeeded
            return NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue) as String?

        } catch let jsonError {

            // JSON serialization failed
            print(jsonError)
            printLog("Error parsing JSON")

            return nil
        }
    }


    // MARK: JS Event Handling

    fileprivate func handleJSEvent(_ eventURL: URL) {

        // Grab the last component of the queryString as string
        let data: String? = eventURL.queryStringComponents()["data"] as? String

        if let host = eventURL.host, let event = YouTubePlayerEvents(rawValue: host) {

            // Check event type and handle accordingly
            switch event {
            case .YouTubeIframeAPIReady:
                ready = true
                break

            case .Ready:
                delegate?.playerReady(self)

                break

            case .StateChange:
                if let newState = YouTubePlayerState(rawValue: data!) {
                    playerState = newState
                    delegate?.playerStateChanged(self, playerState: newState)
                }

                break

            case .PlaybackQualityChange:
                if let newQuality = YouTubePlaybackQuality(rawValue: data!) {
                    playbackQuality = newQuality
                    delegate?.playerQualityChanged(self, playbackQuality: newQuality)
                }

                break
            case .PlayerCurrentTime:
                if let newCurrentTime = Double(data!) {
                    currentTime = newCurrentTime
                    delegate?.playerCurrentTime(self, currentTime: currentTime)
                }
            }
        }
    }


    // MARK: WKNavigationDelegate

    open func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        var action: WKNavigationActionPolicy?
        defer {
            decisionHandler(action ?? .allow)
        }

        guard let url = navigationAction.request.url else { return }

        if url.scheme == "ytplayer" {
            handleJSEvent(url)
            action = .cancel
        }
    }
}

private func printLog(_ strings: CustomStringConvertible...) {
    let toPrint = ["[YouTubePlayer]"] + strings
    print(toPrint, separator: " ", terminator: "\n")
}
#endif
