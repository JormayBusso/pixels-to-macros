import AVFoundation
import Flutter
import UIKit

/// Full-screen barcode scanner that uses AVFoundation (no third-party SDKs).
///
/// Called via MethodChannel "scanBarcode":
///   - Presents a live camera view that detects EAN-8, EAN-13, UPC-A, UPC-E,
///     Code128, QR codes (common for food products).
///   - On successful scan, queries the OpenFoodFacts API (free, no key needed).
///   - Returns a JSON string with: name, kcal_per_100g, protein, carbs, fat,
///     serving_grams (optional), barcode.
///   - Returns nil if the user cancels or the product has no nutrition data.
final class BarcodeScannerPlugin: NSObject {

    // MARK: – Handle MethodChannel call

    static func present(result: @escaping FlutterResult, themeColor: UIColor? = nil,
                        strings: [String: String] = [:]) {
        DispatchQueue.main.async {
            guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
                result(FlutterError(code: "NO_VC",
                    message: "Cannot find root view controller", details: nil))
                return
            }
            let vc = BarcodeScanViewController()
            vc.themeColor = themeColor ?? UIColor(red: 0.18, green: 0.78, blue: 0.45, alpha: 1)
            vc.applyStrings(strings)
            vc.modalPresentationStyle = .fullScreen
            vc.onResult = { nutritionJSON in
                DispatchQueue.main.async {
                    result(nutritionJSON)   // nil == cancelled / not found
                }
            }
            // Find the topmost presented VC to avoid blank presentation.
            var top = rootVC
            while let presented = top.presentedViewController { top = presented }
            top.present(vc, animated: true)
        }
    }
}

// MARK: – View controller

private final class BarcodeScanViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate {

    var onResult: ((String?) -> Void)?
    var themeColor: UIColor = UIColor(red: 0.18, green: 0.78, blue: 0.45, alpha: 1)

    // Localised UI strings (English defaults; overridden from Dart via applyStrings).
    private var instructionText = "Point camera at a food barcode"
    private var cancelText      = "Cancel"
    private var okText          = "OK"
    private var errorTitleText  = "Error"
    private var notFoundTitle   = "Product Not Found"
    private var notFoundBody    = "No nutrition data found for this barcode.\nTry a different product."
    private var scanAgainText   = "Scan Again"

    fileprivate func applyStrings(_ s: [String: String]) {
        if let v = s["instruction"]   { instructionText = v }
        if let v = s["cancel"]        { cancelText = v }
        if let v = s["ok"]            { okText = v }
        if let v = s["error"]         { errorTitleText = v }
        if let v = s["notFoundTitle"] { notFoundTitle = v }
        if let v = s["notFoundBody"]  { notFoundBody = v }
        if let v = s["scanAgain"]     { scanAgainText = v }
    }

    private let session        = AVCaptureSession()
    private var previewLayer   : AVCaptureVideoPreviewLayer!
    private var hasScanned     = false
    private var activityView   : UIActivityIndicatorView?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    // MARK: Camera setup

    private func setupCamera() {
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device) else {
            showError("Camera not available")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
            .ean8, .ean13, .upce, .code128, .qr, .code39, .code93
        ]

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    // MARK: UI

    private func setupUI() {
        // Scan guide box.
        let boxW: CGFloat = 280
        let boxH: CGFloat = 180
        let glow = UIView()
        glow.layer.borderColor = themeColor.withAlphaComponent(0.42).cgColor
        glow.layer.borderWidth = 10
        glow.layer.cornerRadius = 24
        glow.layer.shadowColor = themeColor.cgColor
        glow.layer.shadowOpacity = 0.72
        glow.layer.shadowRadius = 24
        glow.layer.shadowOffset = .zero
        glow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glow)

        let box           = UIView()
        box.layer.borderColor  = themeColor.cgColor
        box.layer.borderWidth  = 4
        box.layer.cornerRadius = 16
        box.layer.shadowColor = themeColor.cgColor
        box.layer.shadowOpacity = 0.65
        box.layer.shadowRadius = 14
        box.layer.shadowOffset = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        let scanLine = UIView()
        scanLine.backgroundColor = themeColor.withAlphaComponent(0.92)
        scanLine.layer.cornerRadius = 2
        scanLine.layer.shadowColor = themeColor.cgColor
        scanLine.layer.shadowOpacity = 0.9
        scanLine.layer.shadowRadius = 10
        scanLine.layer.shadowOffset = .zero
        scanLine.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(scanLine)
        NSLayoutConstraint.activate([
            glow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            glow.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            glow.widthAnchor.constraint(equalToConstant: boxW + 18),
            glow.heightAnchor.constraint(equalToConstant: boxH + 18),
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            box.widthAnchor.constraint(equalToConstant: boxW),
            box.heightAnchor.constraint(equalToConstant: boxH),
            scanLine.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            scanLine.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            scanLine.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            scanLine.heightAnchor.constraint(equalToConstant: 4),
        ])

        let glowPulse = CABasicAnimation(keyPath: "opacity")
        glowPulse.fromValue = 0.45
        glowPulse.toValue = 1.0
        glowPulse.duration = 1.35
        glowPulse.autoreverses = true
        glowPulse.repeatCount = .infinity
        glow.layer.add(glowPulse, forKey: "barcodeGlowPulse")

        let scanPulse = CABasicAnimation(keyPath: "transform.scale.x")
        scanPulse.fromValue = 0.82
        scanPulse.toValue = 1.0
        scanPulse.duration = 0.9
        scanPulse.autoreverses = true
        scanPulse.repeatCount = .infinity
        scanLine.layer.add(scanPulse, forKey: "barcodeScanPulse")

        // Instruction label.
        let label            = UILabel()
        label.text           = instructionText
        label.textColor      = .white
        label.font           = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment  = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.borderColor = themeColor.withAlphaComponent(0.42).cgColor
        label.layer.borderWidth = 1
        label.layer.shadowColor = themeColor.cgColor
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 12
        label.layer.shadowOffset = .zero
        label.layer.cornerRadius = 10
        label.clipsToBounds  = false
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 24),
            label.widthAnchor.constraint(equalToConstant: 300),
            label.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Cancel button.
        let cancel = UIButton(type: .system)
        cancel.setTitle(cancelText, for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.backgroundColor  = UIColor.white.withAlphaComponent(0.25)
        cancel.layer.cornerRadius = 12
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancel.widthAnchor.constraint(equalToConstant: 160),
            cancel.heightAnchor.constraint(equalToConstant: 48),
        ])

        // Activity indicator (shown while fetching nutrition).
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color             = .white
        spinner.hidesWhenStopped  = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        activityView = spinner
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: errorTitleText,
            message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: okText, style: .default) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onResult?(nil) }
        })
        present(alert, animated: true)
    }

    @objc private func didTapCancel() {
        dismiss(animated: true) { [weak self] in self?.onResult?(nil) }
    }

    // MARK: AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let obj  = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue, !code.isEmpty
        else { return }

        hasScanned = true
        session.stopRunning()

        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        activityView?.startAnimating()
        lookupNutrition(barcode: code)
    }

    // MARK: OpenFoodFacts lookup

    /// Barcode variants to try — Open Food Facts often stores UPC-A (12 digits)
    /// as EAN-13 with a leading zero (and vice-versa), and EAN-8 padded to 13.
    /// Trying these normalisations finds many products a single exact lookup
    /// would miss.
    private func barcodeCandidates(_ code: String) -> [String] {
        var out = [code]
        if code.count == 12 { out.append("0" + code) }
        if code.count == 13, code.hasPrefix("0") { out.append(String(code.dropFirst())) }
        if code.count == 8 { out.append(String(repeating: "0", count: 5) + code) }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private func lookupNutrition(barcode: String) {
        tryLookup(candidates: barcodeCandidates(barcode), index: 0, original: barcode)
    }

    /// Try each barcode candidate in turn; the first that returns a product is
    /// used. If none are in Open Food Facts, show the not-found alert.
    private func tryLookup(candidates: [String], index: Int, original: String) {
        guard index < candidates.count else {
            activityView?.stopAnimating()
            showNotFoundAlert(barcode: original)
            return
        }
        let code = candidates[index]
        guard let url = URL(string:
            "https://world.openfoodfacts.org/api/v2/product/\(code).json") else {
            tryLookup(candidates: candidates, index: index + 1, original: original)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Open Food Facts asks every app to send a custom User-Agent.
        request.addValue("PixelsToMacros/1.0 (thesis project)",
                         forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil, let data,
                   let product = BarcodeScanViewController.extractProduct(from: data) {
                    self.activityView?.stopAnimating()
                    self.parseAndFinish(product: product, barcode: original)
                } else {
                    // Not in OFF (or a transient error) — try the next variant.
                    self.tryLookup(candidates: candidates, index: index + 1,
                                   original: original)
                }
            }
        }.resume()
    }

    private static func extractProduct(from data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any]
        else { return nil }
        return product
    }

    /// Resolve energy per 100 g in kcal, trying (in order) the kcal field, the
    /// kJ field converted to kcal, the raw energy field (OFF stores it in kJ),
    /// and finally an Atwater estimate from macros. Many EU products list only
    /// kJ, so this recovers usable data the old kcal-only check rejected.
    private func resolveKcal(_ nutrients: [String: Any],
                             protein: Double, carbs: Double, fat: Double) -> Double? {
        if let k = doubleFrom(nutrients, "energy-kcal_100g"), k > 0 { return k }
        if let kj = doubleFrom(nutrients, "energy-kj_100g"), kj > 0 { return kj / 4.184 }
        if let e = doubleFrom(nutrients, "energy_100g"), e > 0 { return e / 4.184 }
        let fromMacros = protein * 4 + carbs * 4 + fat * 9
        return fromMacros > 0 ? fromMacros : nil
    }

    private func parseAndFinish(product: [String: Any], barcode: String) {
        let nutrients   = product["nutriments"] as? [String: Any] ?? [:]
        let rawName     = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                       ?? (product["generic_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                       ?? ""
        guard !rawName.isEmpty else {
            showNotFoundAlert(barcode: barcode)
            return
        }

        let protein = doubleFrom(nutrients, "proteins_100g")      ?? 0.0
        let carbs   = doubleFrom(nutrients, "carbohydrates_100g") ?? 0.0
        let fat     = doubleFrom(nutrients, "fat_100g")           ?? 0.0
        guard let kcal = resolveKcal(nutrients, protein: protein, carbs: carbs, fat: fat) else {
            // No usable energy (kcal, kJ, or from macros) → not useful.
            showNotFoundAlert(barcode: barcode)
            return
        }

        var result: [String: Any] = [
            "barcode":       barcode,
            "name":          rawName,
            "kcal_per_100g": kcal,
            "protein":       protein,
            "carbs":         carbs,
            "fat":           fat,
            // Fiber
            "fiber":         doubleFrom(nutrients, "fiber_100g")          ?? 0.0,
            // Sugars
            "sugars":        doubleFrom(nutrients, "sugars_100g")         ?? 0.0,
            // Sodium / Salt
            "sodium_mg":     (doubleFrom(nutrients, "sodium_100g") ?? 0.0) * 1000,
            // Vitamins
            "vitamin_a_ug":  doubleFrom(nutrients, "vitamin-a_100g")     ?? 0.0,
            "vitamin_c_mg":  doubleFrom(nutrients, "vitamin-c_100g")     ?? 0.0,
            "vitamin_d_ug":  doubleFrom(nutrients, "vitamin-d_100g")     ?? 0.0,
            "vitamin_e_mg":  doubleFrom(nutrients, "vitamin-e_100g")     ?? 0.0,
            "vitamin_k_ug":  doubleFrom(nutrients, "vitamin-k_100g")     ?? 0.0,
            "vitamin_b12_ug": doubleFrom(nutrients, "vitamin-b12_100g")  ?? 0.0,
            "folate_ug":     doubleFrom(nutrients, "vitamin-b9_100g")    ?? 0.0,
            // Minerals
            "calcium_mg":    doubleFrom(nutrients, "calcium_100g")       ?? 0.0,
            "iron_mg":       doubleFrom(nutrients, "iron_100g")          ?? 0.0,
            "magnesium_mg":  doubleFrom(nutrients, "magnesium_100g")     ?? 0.0,
            "potassium_mg":  doubleFrom(nutrients, "potassium_100g")     ?? 0.0,
            "zinc_mg":       doubleFrom(nutrients, "zinc_100g")          ?? 0.0,
            // Saturated fat
            "saturated_fat": doubleFrom(nutrients, "saturated-fat_100g") ?? 0.0,
            // Cholesterol
            "cholesterol_mg": doubleFrom(nutrients, "cholesterol_100g")  ?? 0.0,
        ]

        if let sqty = product["serving_quantity"] {
            if let n = sqty as? NSNumber { result["serving_grams"] = n.doubleValue }
            else if let s = sqty as? String, let v = Double(s) { result["serving_grams"] = v }
        }

        guard let jsonData   = try? JSONSerialization.data(withJSONObject: result),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            finishWith(json: nil, barcode: barcode, error: "JSON encoding error")
            return
        }

        dismiss(animated: true) { [weak self] in self?.onResult?(jsonString) }
    }

    private func doubleFrom(_ dict: [String: Any], _ key: String) -> Double? {
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        if let s = dict[key] as? String   { return Double(s) }
        return nil
    }

    private func showNotFoundAlert(barcode: String) {
        let alert = UIAlertController(
            title:   notFoundTitle,
            message: notFoundBody,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: scanAgainText, style: .default) { [weak self] _ in
            self?.hasScanned = false
            DispatchQueue.global(qos: .userInitiated).async { self?.session.startRunning() }
        })
        alert.addAction(UIAlertAction(title: cancelText, style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onResult?(nil) }
        })
        present(alert, animated: true)
    }

    private func finishWith(json: String?, barcode: String, error: String) {
        print("[BarcodeScannerPlugin] \(error) (barcode: \(barcode))")
        showNotFoundAlert(barcode: barcode)
    }
}
