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

    static func present(result: @escaping FlutterResult, themeColor: UIColor? = nil) {
        DispatchQueue.main.async {
            guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
                result(FlutterError(code: "NO_VC",
                    message: "Cannot find root view controller", details: nil))
                return
            }
            let vc = BarcodeScanViewController()
            vc.themeColor = themeColor ?? UIColor(red: 0.18, green: 0.78, blue: 0.45, alpha: 1)
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
        let box           = UIView()
        box.layer.borderColor  = themeColor.cgColor
        box.layer.borderWidth  = 2.5
        box.layer.cornerRadius = 16
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            box.widthAnchor.constraint(equalToConstant: boxW),
            box.heightAnchor.constraint(equalToConstant: boxH),
        ])

        // Instruction label.
        let label            = UILabel()
        label.text           = "Point camera at a food barcode"
        label.textColor      = .white
        label.font           = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment  = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 10
        label.clipsToBounds  = true
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
        cancel.setTitle("Cancel", for: .normal)
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
        let alert = UIAlertController(title: "Error",
            message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
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

    private func lookupNutrition(barcode: String) {
        let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlStr) else {
            finishWith(json: nil, barcode: barcode, error: "Invalid barcode URL")
            return
        }

        var request        = URLRequest(url: url)
        request.timeoutInterval = 8
        request.addValue("PixelsToMacros/1.0 (thesis project)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activityView?.stopAnimating()

                if let error {
                    self.finishWith(json: nil, barcode: barcode,
                                    error: "Network error: \(error.localizedDescription)")
                    return
                }
                guard let data else {
                    self.finishWith(json: nil, barcode: barcode, error: "No data received")
                    return
                }
                self.parseAndFinish(data: data, barcode: barcode)
            }
        }.resume()
    }

    private func parseAndFinish(data: Data, barcode: String) {
        guard
            let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (json["status"] as? Int) == 1,
            let product  = json["product"] as? [String: Any]
        else {
            showNotFoundAlert(barcode: barcode)
            return
        }

        let nutrients   = product["nutriments"] as? [String: Any] ?? [:]
        let rawName     = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                       ?? (product["generic_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                       ?? ""
        guard !rawName.isEmpty else {
            showNotFoundAlert(barcode: barcode)
            return
        }

        guard let kcal = doubleFrom(nutrients, "energy-kcal_100g") else {
            // No calorie data → not useful.
            showNotFoundAlert(barcode: barcode)
            return
        }

        var result: [String: Any] = [
            "barcode":       barcode,
            "name":          rawName,
            "kcal_per_100g": kcal,
            "protein":       doubleFrom(nutrients, "proteins_100g")       ?? 0.0,
            "carbs":         doubleFrom(nutrients, "carbohydrates_100g")  ?? 0.0,
            "fat":           doubleFrom(nutrients, "fat_100g")            ?? 0.0,
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
            title:   "Product Not Found",
            message: "No nutrition data found for barcode \(barcode).\nTry a different product.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Scan Again", style: .default) { [weak self] _ in
            self?.hasScanned = false
            DispatchQueue.global(qos: .userInitiated).async { self?.session.startRunning() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onResult?(nil) }
        })
        present(alert, animated: true)
    }

    private func finishWith(json: String?, barcode: String, error: String) {
        print("[BarcodeScannerPlugin] \(error) (barcode: \(barcode))")
        showNotFoundAlert(barcode: barcode)
    }
}
