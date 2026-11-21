import Foundation

struct AdSDK {
    let key: String
    let name: String
    let frameworks: [String]
    let classPrefixes: [String]
    let bundles: [String]
}

enum AdSDKDatabase {
    static let all: [AdSDK] = [
        AdSDK(
            key: "BUAdSDK",
            name: "穿山甲 / Pangle",
            frameworks: ["BUAdSDK.framework"],
            classPrefixes: ["BUAdSDKManager", "BUAdNativeAd", "PAGAdSDK"],
            bundles: ["BUAdSDK.bundle"]
        ),
        AdSDK(
            key: "TTAdSDK",
            name: "巨量广告",
            frameworks: ["TTAdSDK.framework"],
            classPrefixes: ["TTAdSdk", "TTAdNative"],
            bundles: []
        ),
        AdSDK(
            key: "KSAdSDK",
            name: "快手联盟",
            frameworks: ["KSAdSDK.framework"],
            classPrefixes: ["KSAdSDKManager", "KSAdNativeAd"],
            bundles: []
        ),
        AdSDK(
            key: "GDTMobSDK",
            name: "优量汇 / 广点通",
            frameworks: ["GDTMobSDK.framework"],
            classPrefixes: ["GDTMobBannerView", "GDTMobInterstitial"],
            bundles: []
        ),
        AdSDK(
            key: "BaiduMobAdSDK",
            name: "百度联盟",
            frameworks: ["BaiduMobAdSDK.framework"],
            classPrefixes: ["BaiduMobAdView", "BaiduMobAdManager"],
            bundles: []
        ),
        AdSDK(
            key: "GoogleMobileAds",
            name: "AdMob",
            frameworks: ["GoogleMobileAds.framework"],
            classPrefixes: ["GADBannerView", "GADInterstitialAd", "GADMobileAds"],
            bundles: []
        ),
        AdSDK(
            key: "AppLovinSDK",
            name: "AppLovin",
            frameworks: ["AppLovinSDK.framework"],
            classPrefixes: ["ALSdk", "ALAdView"],
            bundles: []
        ),
        AdSDK(
            key: "IronSource",
            name: "ironSource",
            frameworks: ["IronSource.framework"],
            classPrefixes: ["IronSource"],
            bundles: []
        ),
        AdSDK(
            key: "UnityAds",
            name: "Unity Ads",
            frameworks: ["UnityAds.framework"],
            classPrefixes: ["UnityAds", "UADSBannerView"],
            bundles: []
        ),
        AdSDK(
            key: "Mintegral",
            name: "Mintegral",
            frameworks: ["MintegralAdSDK.framework", "MintegralSDK.framework"],
            classPrefixes: ["MTGAdView", "MintegralAdSDK"],
            bundles: []
        ),
    ]
}
