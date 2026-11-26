#pragma once
#include <functional>
#include <string>
#include <vector>

struct MenuHost {
    // Return an empty string while the game adapter is unavailable.
    std::function<std::string()> currentArea;
    std::function<bool(bool)> saveDetails;
};

class Menu {
public:
    Menu(MenuHost host, bool showDetails);
    Menu(const Menu&) = delete;
    Menu& operator=(const Menu&) = delete;
    void addPage(std::string label, std::function<void()> draw);
    void draw();
private:
    struct Page { std::string label; std::function<void()> draw; };
    std::vector<Page> pages;
    MenuHost host;
    bool details;
    bool saveFailed = false;
    bool open = true;
    std::string lastArea;
    void overview();
    void settings();
};
