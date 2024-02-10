//
//  LoginView.swift
//  MattermostMeetingStatus
//
//  Created by Max-Heinrich Laves on 02.02.24.
//

import SwiftUI

struct LoginView: View {
    @Binding var isPresented: Bool
    @Binding var mattermostServer: String
    @Binding var mattermostUserId: String
    @Binding var mattermostAuthToken: String
    @Binding var showAlert: Bool
    @Binding var currentError: MattermostStatusError
    
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var currentDataTask: URLSessionDataTask?
    @State private var showLoginAlert = false
    @State private var loginError: Error?

    var body: some View {
        ZStack {
            VStack {
                TextField("Mattermost server", text: $mattermostServer)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Username", text: $username)
                    .font(.system(.body, design: .monospaced))
                    .textContentType(.username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                SecureField("Password", text: $password)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Button("Cancel") {
                        cancel()
                    }
                    Button("Login") {
                        loginUser()
                    }
                }
            }
            .disabled(isLoading)
            .frame(width: 250)
            .padding()
            .onSubmit {
                loginUser()
            }
            .alert("Login Error", isPresented: $showLoginAlert) {
                Button("Ok") {
                    showLoginAlert.toggle()
                }
            } message: {
                Text(loginError?.localizedDescription ?? "Unknown error")
            }
            if isLoading {
                Color.black.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                    VStack {
                        ProgressView("Click to cancel...")  // ProgressView("Logging in...")
                    }
                )
            }
        }
        .onTapGesture {
            if isLoading {
                cancelRequest()
            }
        }
    }
    
    func loginUser() {
        isLoading = true
        getMattermostAuthToken() { result in
            switch result {
            case .success(let data):
                mattermostAuthToken = data["authToken"] ?? ""
                mattermostUserId = data["userId"] ?? ""
                isLoading = false
                isPresented = false
            case .failure(let error):
                // Handle the failure with the specific error
                print("Error: \(error)")
                cancelRequest()
                
                // error code -999 is user initiated cancel, don't show alert
                if (error as NSError).code != -999 {
                    loginError = error
                    showLoginAlert.toggle()
                }
            }
        }
    }
    
    func cancel() {
        cancelRequest()
        isPresented = false
    }
    
    func cancelRequest() {
        isLoading = false
        currentDataTask?.cancel()
    }
    
    func getMattermostAuthToken(completion: @escaping (Result<[String: String], Error>) -> Void) {
        guard let loginURL = getServerUrl(urlString: mattermostServer)?.appendingPathComponent("api/v4/users/login") else {
            currentError = .serverUrl
            showAlert = true
            return
        }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let loginData = ["login_id": username, "password": password]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: loginData)
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }

        currentDataTask = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response")
                return
            }
            
            var result: [String: String] = [:]
            
            if let data = data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    if let errorMessage = json?["message"] as? String {
                        completion(.failure(NSError(domain: "MattermostAPIError", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    }
                    else if let userId = json?["id"] as? String {
                        if let authToken = httpResponse.allHeaderFields["Token"] as? String {
                            print("Token: \(authToken)")
                            result["authToken"] = authToken
                        } else {
                            let errorMessage = "Token not found in the header"
                            print(errorMessage)
                            completion(.failure(NSError(domain: "MattermostAPIError", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        }
                        result["userId"] = userId
                        completion(.success(result))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            
        }
        currentDataTask?.resume()  // if currentDataTask is nil, entire experssion evaluates to nil
    }
}
