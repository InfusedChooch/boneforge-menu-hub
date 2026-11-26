#include "Menu.h"
#include "identity.h"
#include "imgui.h"
#include <utility>

Menu::Menu(MenuHost adapter, bool showDetails) : host(std::move(adapter)), details(showDetails) {
    addPage("Overview", [this] { overview(); });
    addPage("Settings", [this] { settings(); });
}

void Menu::addPage(std::string label, std::function<void()> drawPage) {
    pages.push_back({std::move(label), std::move(drawPage)});
}

void Menu::draw() {
    if (ImGui::IsKeyPressed(ImGuiKey_F8, false)) open = !open;
    if (!open) return;
    ImGui::SetNextWindowSize(ImVec2(440, 235), ImGuiCond_FirstUseEver);
    if (ImGui::Begin(MENU_NAME, nullptr) && ImGui::BeginTabBar("Pages")) {
        for (const auto& page : pages) {
            if (ImGui::BeginTabItem(page.label.c_str())) {
                page.draw();
                ImGui::EndTabItem();
            }
        }
        ImGui::EndTabBar();
    }
    ImGui::End();
}

void Menu::overview() {
    ImGui::TextUnformatted(MENU_NAME "  " MENU_VERSION);
    const auto area = host.currentArea ? host.currentArea() : std::string{};
    ImGui::TextUnformatted(area.empty() ? "Game adapter unavailable" : "Game adapter ready");
    ImGui::BeginDisabled(area.empty());
    if (ImGui::Button("Read current area")) lastArea = area;
    ImGui::EndDisabled();
    if (area.empty()) {
        lastArea.clear();
        ImGui::TextUnformatted("Waiting for a game area from the host.");
    } else if (!lastArea.empty()) {
        ImGui::TextUnformatted(lastArea.c_str());
    }
    if (details) ImGui::TextDisabled("F8 opens or hides the menu.");
}

void Menu::settings() {
    bool desired = details;
    if (ImGui::Checkbox("Show control hints", &desired)) {
        saveFailed = !host.saveDetails || !host.saveDetails(desired);
        if (!saveFailed) details = desired;
    }
    if (saveFailed) ImGui::TextUnformatted("Could not save this preference.");
}
