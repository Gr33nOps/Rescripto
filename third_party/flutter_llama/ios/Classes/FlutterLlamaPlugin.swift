import Flutter
import UIKit
import Foundation

/**
 * FlutterLlamaPlugin - плагин для работы с llama.cpp моделями на iOS
 * 
 * Поддерживает:
 * - Загрузку GGUF моделей
 * - GPU ускорение через Metal
 * - Потоковую и обычную генерацию
 */
@available(iOS 13.0, *)
public class FlutterLlamaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var modelLoaded = false
    private var modelPath: String?
    private let queue = DispatchQueue(label: "net.nativemind.flutter_llama", qos: .userInitiated)
    private var eventSink: FlutterEventSink?
    private var shouldStop = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_llama",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "flutter_llama/stream",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = FlutterLlamaPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        
        NSLog("[FlutterLlama] Plugin registered")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            loadModel(call: call, result: result)
        case "generate":
            generate(call: call, result: result)
        case "generateStream":
            generateStream(call: call, result: result)
        case "unloadModel":
            unloadModel(result: result)
        case "getModelInfo":
            getModelInfo(result: result)
        case "stopGeneration":
            stopGeneration(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        shouldStop = true
        rescripto_llama_stop_generation()
        return nil
    }
    
    // MARK: - Load Model
    
    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let modelPath = args["modelPath"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing required arguments",
                        details: nil
                    ))
                }
                return
            }
            
            let nThreads = args["nThreads"] as? Int ?? 4
            let nGpuLayers = args["nGpuLayers"] as? Int ?? 0
            let contextSize = args["contextSize"] as? Int ?? 2048
            let batchSize = args["batchSize"] as? Int ?? 512
            let useGpu = args["useGpu"] as? Bool ?? true
            let verbose = args["verbose"] as? Bool ?? false
            
            // Check if model file exists
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: modelPath) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "MODEL_NOT_FOUND",
                        message: "Model file not found: \(modelPath)",
                        details: nil
                    ))
                }
                return
            }
            
            self.modelPath = modelPath
            
            // Initialize model through llama.cpp C++ bridge
            let success = modelPath.withCString { path in
                rescripto_llama_init_model(
                    path,
                    Int32(nThreads),
                    Int32(nGpuLayers),
                    Int32(contextSize),
                    Int32(batchSize),
                    useGpu,
                    verbose
                )
            }
            
            self.modelLoaded = success
            
            DispatchQueue.main.async {
                if success {
                    NSLog("[FlutterLlama] Model loaded: \(modelPath)")
                    NSLog("[FlutterLlama] GPU layers: \(nGpuLayers), threads: \(nThreads), context: \(contextSize)")
                    result(true)
                } else {
                    result(FlutterError(
                        code: "INIT_FAILED",
                        message: "Failed to initialize model",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - Generate (blocking)
    
    private func generate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            let stopSequences = (args["stopSequences"] as? [String]) ?? []
            
            self.shouldStop = false
            let startTime = Date()
            
            // Generate through llama.cpp C++ bridge
            var outputBuffer = [CChar](
                repeating: 0,
                count: max(65_536, maxTokens * 32)
            )
            var tokensGenerated: Int32 = 0

            let outputCount = outputBuffer.count
            let success = prompt.withCString { promptPointer in
                outputBuffer.withUnsafeMutableBufferPointer { outputPointer in
                    rescripto_llama_generate(
                        promptPointer,
                        Float(temperature),
                        Float(topP),
                        Int32(topK),
                        Int32(maxTokens),
                        Float(repeatPenalty),
                        outputPointer.baseAddress!,
                        Int32(outputCount),
                        &tokensGenerated
                    )
                }
            }
            
            let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
            
            DispatchQueue.main.async {
                if success {
                    let responseText = self.trimAtStop(
                        String(cString: outputBuffer),
                        stopSequences: stopSequences
                    )
                    let response: [String: Any] = [
                        "text": responseText,
                        "tokensGenerated": Int(tokensGenerated),
                        "generationTimeMs": generationTime
                    ]
                    NSLog("[FlutterLlama] Generated: \(tokensGenerated) tokens in \(generationTime)ms")
                    result(response)
                } else {
                    result(FlutterError(
                        code: "GENERATION_FAILED",
                        message: "Failed to generate response",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - Generate Stream
    
    private func generateStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        guard let eventSink = self.eventSink else {
            result(FlutterError(
                code: "NO_EVENT_SINK",
                message: "Event channel not initialized",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            let stopSequences = (args["stopSequences"] as? [String]) ?? []
            
            self.shouldStop = false
            
            // Initialize streaming generation
            let initialized = prompt.withCString { promptPointer in
                rescripto_llama_generate_stream_init(
                    promptPointer,
                    Float(temperature),
                    Float(topP),
                    Int32(topK),
                    Int32(maxTokens),
                    Float(repeatPenalty)
                )
            }
            guard initialized else {
                DispatchQueue.main.async {
                    eventSink(FlutterError(
                        code: "GENERATION_FAILED",
                        message: "Prompt exceeds context or stream initialization failed",
                        details: nil
                    ))
                    result(FlutterError(
                        code: "GENERATION_FAILED",
                        message: "Stream initialization failed",
                        details: nil
                    ))
                }
                return
            }
            
            // Stream tokens one by one
            var tokenBuffer = [CChar](repeating: 0, count: 4096)
            var pending = ""
            let tailLength = max(0, (stopSequences.map(\.count).max() ?? 1) - 1)
            var stoppedAtSequence = false
            while true {
                let tokenCount = tokenBuffer.count
                let hasMore = tokenBuffer.withUnsafeMutableBufferPointer { pointer in
                    rescripto_llama_generate_stream_next(
                        pointer.baseAddress!,
                        Int32(tokenCount)
                    )
                }

                if hasMore {
                    let token = String(cString: tokenBuffer)
                    pending.append(token)
                    if let stopIndex = self.firstStopIndex(
                        in: pending,
                        stopSequences: stopSequences
                    ) {
                        let safe = String(pending[..<stopIndex])
                        if !safe.isEmpty {
                            DispatchQueue.main.async { eventSink(safe) }
                        }
                        stoppedAtSequence = true
                        rescripto_llama_stop_generation()
                        break
                    }
                    let safeCount = pending.count - tailLength
                    if safeCount > 0 {
                        let end = pending.index(pending.startIndex, offsetBy: safeCount)
                        let safe = String(pending[..<end])
                        pending.removeSubrange(..<end)
                        DispatchQueue.main.async { eventSink(safe) }
                    }
                } else {
                    break
                }
            }
            if !stoppedAtSequence && !pending.isEmpty {
                DispatchQueue.main.async { eventSink(pending) }
            }

            rescripto_llama_generate_stream_end()
            
            DispatchQueue.main.async {
                eventSink(FlutterEndOfEventStream)
                result(nil)
            }
        }
    }
    
    // MARK: - Unload Model
    
    private func unloadModel(result: @escaping FlutterResult) {
        shouldStop = true
        rescripto_llama_stop_generation()
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.modelLoaded {
                rescripto_llama_free_model()
                self.modelLoaded = false
                self.modelPath = nil
                NSLog("[FlutterLlama] Model unloaded")
            }
            DispatchQueue.main.async { result(nil) }
        }
    }
    
    // MARK: - Get Model Info
    
    private func getModelInfo(result: @escaping FlutterResult) {
        guard modelLoaded, let modelPath = modelPath else {
            result(nil)
            return
        }
        
        var nParams: Int64 = 0
        var nLayers: Int32 = 0
        var contextSize: Int32 = 0
        
        rescripto_llama_get_model_info(&nParams, &nLayers, &contextSize)
        
        let info: [String: Any] = [
            "modelPath": modelPath,
            "nParams": nParams,
            "nLayers": nLayers,
            "contextSize": contextSize
        ]
        
        result(info)
    }
    
    // MARK: - Stop Generation
    
    private func stopGeneration(result: @escaping FlutterResult) {
        shouldStop = true
        rescripto_llama_stop_generation()
        result(nil)
    }

    private func trimAtStop(_ text: String, stopSequences: [String]) -> String {
        guard let index = firstStopIndex(in: text, stopSequences: stopSequences) else {
            return text
        }
        return String(text[..<index])
    }

    private func firstStopIndex(
        in text: String,
        stopSequences: [String]
    ) -> String.Index? {
        stopSequences
            .filter { !$0.isEmpty }
            .compactMap { text.range(of: $0)?.lowerBound }
            .min()
    }
}
