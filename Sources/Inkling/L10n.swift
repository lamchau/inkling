import Foundation

enum L10n {
    private static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Inkling_Inkling.bundle"),
            let resourceBundle = Bundle(url: resourceURL)
        {
            return resourceBundle
        }

        return .module
    }()

    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle)
    }
}
