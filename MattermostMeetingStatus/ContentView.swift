//
//  ContentView.swift
//  MattermostMeetingStatus
//
//  Created by Max-Heinrich Laves on 24.01.24.
//

import SwiftUI
import EventKit
// import BackgroundTasks

enum MattermostStatus: String {
    case doNotDisturb = "dnd"
    case online = "online"
    case away = "away"
}

enum MattermostStatusError: String, Error {
    case serverUrl = "Could not parse the server URL."
    case urlRequest = "Could not connect to the server."
    case httpResponse = "HTTP response error."
    case createJson = "Could not create JSON payload."
    case unknown = "Unknown error."
}

struct ContentView: View {
    @State private var isRunning = false
    @State private var showAlert = false
    @State private var currentError: MattermostStatusError = .unknown
    @State private var calendarAccessGranted = false
    @State private var selectedCalendar: EKCalendar?
    @State private var calendars: [EKCalendar]? = []
    @State private var currentEventTitle = ""
    @State private var timer: Timer?
    @State private var updateInterval = 60
    @State private var setStatusIsRunning = false
    @State private var showLoginSheet = false
    @State private var username = ""
    @State private var password = ""

    @AppStorage("mattermostServer") private var mattermostServer = ""
    @AppStorage("mattermostUserId") private var mattermostUserId = ""
    @AppStorage("mattermostAuthToken") private var mattermostAuthToken = ""
        

    var body: some View {
        VStack {
            HStack {
                Picker("Calendar", selection: $selectedCalendar) {
                    if let calendars = calendars {
                        ForEach(calendars, id: \.self) { calendar in
                                HStack {
                                    Image(systemName: "square.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color(calendar.color), .black)
                                    Text(calendar.title)
                                }.tag(Optional(calendar))
                        }
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
                Spacer()
                Button(action: {
                    if isRunning {
                        timer?.invalidate()
                        timer = nil
                        isRunning = false
                        currentEventTitle = ""
                        setMattermostStatus(.online)
                    } else {
                        if let selectedCalendar = selectedCalendar {
                            isRunning = true
                            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(updateInterval), repeats: true) { _ in
                                if setStatusIsRunning {
                                    return
                                }
                                setStatusIsRunning = true
                                getCurrentEvent(for: selectedCalendar) { event in
                                    if let event = event {
                                        if let title = event.title {
                                            currentEventTitle = title
                                            setMattermostStatus(.doNotDisturb)  // TODO: revert back on failure
                                        }
                                    } else {
                                        // Handle no active event
                                        currentEventTitle = ""
                                        setMattermostStatus(.online)
                                    }
                                }
                            }
                            // don't wait for the first time
                            timer?.fire()
                        }
                    }
                }, label: {
                    Text(isRunning ? "Stop" : "Start").frame(minWidth: 40)
                })
            }
            HStack {
                Text("Current event:")
                Spacer()
                Text(currentEventTitle).lineLimit(1).truncationMode(.middle)
                Spacer()
            }.frame(minHeight: 20)
            HStack {
                Text("Update interval:")
                Spacer()
                Stepper {
                    Text("\(updateInterval)")
                } onIncrement: {
                    if updateInterval < 3600 {
                        updateInterval = updateInterval + 5
                    }
                } onDecrement: {
                    if updateInterval > 10 {
                        updateInterval = updateInterval - 5
                    }
                }
                Text("seconds")
                Spacer()
            }.disabled(isRunning)
            VStack {
                // make the monospaced font a little bit smaller
                let fontSize = NSFont.systemFontSize
                TextField("Mattermost server", text: $mattermostServer)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Mattermost user ID", text: $mattermostUserId)
                    .font(.system(size: fontSize , design: .monospaced))
                    .textContentType(.username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Mattermost auth token", text: $mattermostAuthToken)
                    .font(.system(size: fontSize , design: .monospaced))
                    .textContentType(.username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Button {
                        showLoginSheet.toggle()
                    } label: {
                        Text("Get user ID and auth token")
                    }
                    Spacer()
                    Button {
                        // TODO: Show help sheet
                    } label: {
                        Text("Help")//.frame(minWidth: 60) TODO: Check design
                    }

                }
                
            }
            .disabled(isRunning)
        }
        .onAppear {
            getAllCalendars {
                calendars = $0
                if let firstCalendar = calendars?.first {
                    selectedCalendar = firstCalendar
                }
            }
            getDefaultCalendar {
                if let defaultCalendar = $0 {
                    selectedCalendar = defaultCalendar
                }
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("Stop", role: .cancel) {
                timer?.invalidate()
                timer = nil
                isRunning = false
                setStatusIsRunning = false
                currentEventTitle = ""
                currentError = .unknown  // reset currentError
            }
        } message: {
            Text(currentError.rawValue)
        }
        .sheet(isPresented: $showLoginSheet, content: {
            LoginView(isPresented: $showLoginSheet, mattermostServer: $mattermostServer, mattermostUserId: $mattermostUserId, mattermostAuthToken: $mattermostAuthToken, showAlert: $showAlert, currentError: $currentError)
        })
        .padding()
        .frame(width: 300, height: 215)
    }
    
    func setMattermostStatus(_ status: MattermostStatus) {
        if let apiUrl = getStatusUrl(urlString: mattermostServer) {
            // Create the request
            var request = URLRequest(url: apiUrl)
            request.httpMethod = "PUT"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(mattermostAuthToken)", forHTTPHeaderField: "Authorization")
            
            // Create the JSON payload
            let jsonPayload: [String: Any] = ["user_id": mattermostUserId, "status": status.rawValue]
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload)
                request.httpBody = jsonData
            } catch {
                print("Error creating JSON payload: \(error)")
                DispatchQueue.main.async {
                    currentError = .createJson
                    showAlert = true
                }
                return
            }
                        
            // Make the request
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    print("Error: \(error)")
                    DispatchQueue.main.async {
                        currentError = .urlRequest
                        showAlert = true
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        print("Status Code: \(httpResponse.statusCode)")
                        DispatchQueue.main.async {
                            currentError = .httpResponse
                            showAlert = true
                        }
                        return
                    }
                    // if everything went fine, remove error again (e.g., due to connection hiccup)
                    DispatchQueue.main.async {
                        currentError = .unknown
                        showAlert = false
                        setStatusIsRunning = false
                    }
                }
            }
            task.resume()
        } else {
            currentError = .serverUrl
            showAlert = true
        }
    }
}

func getServerUrl(urlString: String) -> URL? {
    if urlString.isEmpty {
        return nil
    }
    
    var urlString = urlString
    
    // Check if the URL already starts with "https://"
    if !urlString.lowercased().hasPrefix("https://") {
        urlString = "https://" + urlString
    }
    
    if !urlString.hasSuffix("/") {
        urlString = urlString + "/"
    }
    
    return URL(string: urlString)
}

func getStatusUrl(urlString: String) -> URL? {
    let url = getServerUrl(urlString: urlString)
    return url?.appendingPathComponent("api/v4/users/me/status")
}

func getAllCalendars(completion: @escaping ([EKCalendar]?) -> Void) {
    let eventStore = EKEventStore()

    eventStore.requestAccess(to: .event) { (granted, error) in
        guard granted, error == nil else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        let userCalendars = eventStore.calendars(for: .event)
        DispatchQueue.main.async {
            completion(userCalendars)
        }
    }
    completion(nil)
}

func getDefaultCalendar(completion: @escaping (EKCalendar?) -> Void) {
    let eventStore = EKEventStore()

    eventStore.requestAccess(to: .event) { (granted, error) in
        guard granted, error == nil else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        let defaultCalendar = eventStore.defaultCalendarForNewEvents
        DispatchQueue.main.async {
            completion(defaultCalendar)
        }
    }
    completion(nil)
}

// TODO: Can be used to watch multiple calendars by [EKCalendar]
func getCurrentEvent(for calendar: EKCalendar, completion: @escaping (EKEvent?) -> Void) {
    // Create an instance of EKEventStore
    let eventStore = EKEventStore()

    // Request access to the user's calendar
    eventStore.requestAccess(to: .event) { (granted, error) in
        if granted && error == nil {
            // Access granted, fetch the user's calendar events
            let currentDate = Date()
            let calendarDate = Calendar.current
            let endDate = calendarDate.date(byAdding: .year, value: 1, to: currentDate) // Set an end date in the future

            let predicate = eventStore.predicateForEvents(withStart: currentDate, end: endDate!, calendars: [calendar])
            let events = eventStore.events(matching: predicate).filter { !$0.isAllDay }

            // Sort the events by start date
            let sortedEvents = events.sorted { $0.startDate < $1.startDate }

            if let nextEvent = sortedEvents.first, nextEvent.startDate <= currentDate && nextEvent.endDate >= currentDate {
                // The next event is currently running
                completion(nextEvent)
            }
            else {
                completion(nil)
            }
        } else {
            print("Access to calendar not granted")
            completion(nil)
        }
    }
}

#Preview {
    ContentView()
}
