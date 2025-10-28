//
//  Prompts.swift
//  Found
//
//  Created by lixindong on 2023/4/21.
//
import Combine
import Foundation
import SwiftUI

class PromptStore: ObservableObject {

    @Published var prompts: [PromptCategory]
    @Published var searchText: String = ""
    @Published var selected: Int = 0
    @Published var filteredPrompts: [PromptTemplate] = []
    
    var cancellables = Set<AnyCancellable>()
    var task: Task<(), Never>?
    
    var categoryTask: Task<(), Never>?
    var categoryCancellables = Set<AnyCancellable>()

    init() {
//        prompts = [
//            PromptCategory(title: "法律", prompts: [
//                PromptTemplate(title: "New", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "New1", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "NewLaw", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "NewCom", desc: "Hola", prompt: "Prompt"),
//            ]),
//            PromptCategory(title: "文学", prompts: [
//                PromptTemplate(title: "Some", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "Lala", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "CarYellow", desc: "Hola", prompt: "Prompt"),
//                PromptTemplate(title: "NewCoOm", desc: "Hola", prompt: "Prompt"),
//            ])
//        ]
        do {
            // DEPRECATED: `selectedLanguage` in UserDefaults is no longer used.
            // Use the app's current language (preferred localization) instead.
            let preferredLang = Bundle.main.preferredLocalizations.first?.lowercased()
                ?? Locale.preferredLanguages.first?.lowercased()
                ?? "en"
            let isChinese = preferredLang.hasPrefix("zh")
            let filename = isChinese ? "prompts_zh" : "prompts"
            prompts = try parseJSONFile(filename: filename)
            filteredPrompts = prompts.flatMap({ category in
                category.prompts
            })
        } catch {
            print(error)
            prompts = []
            filteredPrompts = []
        }
        startObserve()
    }

    func startObserve() {
        $searchText
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                self.task?.cancel()
                self.selected = 0
                self.task = Task { await self.filter(keyword: value) }
            }
            .store(in: &cancellables)
        
        $selected
            .sink { [weak self] value in
                guard let self = self else { return }
                self.categoryTask?.cancel()
                self.categoryTask = Task { await self.filter(category: self.selected == 0 ? "" : self.prompts[self.selected - 1].title)}
            }.store(in: &categoryCancellables)
    }

    func filter(keyword: String = "", category: String = "") async {
        print("search for keyword \(keyword)")
        Task { @MainActor in
            withAnimation {
                filteredPrompts = prompts
                    .filter({ cate in
                        category.isEmpty || cate.title == category
                    })
                    .flatMap({ cate in
                        cate.prompts
                    })
                    .filter({ prompt in
                        keyword.isEmpty || prompt.prompt.lowercased().contains(keyword.lowercased()) || prompt.title.lowercased().contains(keyword.lowercased())
                    })
                    .reduce(into: []) { (result, person) in
                        if !result.contains(where: { $0.title
                            == person.title }) {
                            result.append(person)
                        }
                    }
            }
        }
    }
}

func parseJSONFile(filename: String) throws -> [PromptCategory] {
    if let path = Bundle.main.path(forResource: filename, ofType: "json") {
        let url = URL(fileURLWithPath: path.string)
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let categories = try decoder.decode([PromptCategory].self, from: data)
            return categories
        } catch {
            print("parse error \(error)")
            throw error
        }
    } else {
        print("file not found")
        throw NSError(domain: "com.yourdomain", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"])
    }
}
