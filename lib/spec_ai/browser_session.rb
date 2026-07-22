# frozen_string_literal: true

require "selenium-webdriver"

module SpecAI
  # Interface is fixed by the task brief (navigate/find/click/type/select_option/screenshot/
  # execute_script/wait_for/snapshot/element_metadata/suggestions_for all live on the session),
  # so this stays over Metrics/ClassLength rather than being split for its own sake.
  class BrowserSession # rubocop:disable Metrics/ClassLength
    STRATEGIES = %w[id css xpath name link_text].freeze
    BROWSERS = %w[chrome firefox edge safari].freeze
    # Transport-level failures that mean the driver connection is gone: treat the
    # session as dead rather than letting a raw socket error escape the guard.
    CONNECTION_ERRORS = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED,
      EOFError, IOError, SocketError
    ].freeze
    DEFAULT_TIMEOUT = 10
    HEADLESS_FLAGS = { "chrome" => "--headless=new", "edge" => "--headless=new", "firefox" => "-headless" }.freeze

    SNAPSHOT_JS = <<~JS
      const sel = "a, button, input, select, textarea, [role=button], h1, h2, h3";
      return Array.from(document.querySelectorAll(sel)).slice(0, 100).map((el) => ({
        tag: el.tagName.toLowerCase(),
        id: el.id || null,
        name: el.getAttribute("name"),
        type: el.getAttribute("type"),
        text: (el.innerText || (el.type === "password" ? "" : el.value) || "").trim().slice(0, 60),
        href: el.getAttribute("href")
      }));
    JS

    # Counts how many elements a Capybara idiomatic locator (link/button text,
    # or a field's fill_in key) would match, so the renderer only uses the
    # idiomatic form when it is unambiguous. kind + key are passed as arguments
    # (arguments[0], arguments[1]) so no value is interpolated into the script.
    UNIQUENESS_JS = <<~JS
      const kind = arguments[0], key = arguments[1];
      const txt = (el) => (el.innerText || el.value || el.textContent || "").trim();
      let els = [];
      if (kind === "link") {
        els = Array.from(document.querySelectorAll("a"))
          .filter((a) => a.id === key || txt(a) === key || a.getAttribute("title") === key);
      } else if (kind === "button") {
        els = Array.from(document.querySelectorAll("button, input[type=submit], input[type=button], input[type=image]"))
          .filter((b) => b.id === key || b.value === key || txt(b) === key || b.getAttribute("title") === key);
      } else {
        const direct = Array.from(document.querySelectorAll("input, textarea, select"))
          .filter((f) => f.id === key || f.name === key || f.getAttribute("placeholder") === key);
        const labeled = Array.from(document.querySelectorAll("label"))
          .filter((l) => l.textContent.trim() === key)
          .map((l) => l.htmlFor ? document.getElementById(l.htmlFor) : l.querySelector("input, textarea, select"))
          .filter(Boolean);
        els = Array.from(new Set(direct.concat(labeled)));
      }
      return els.length;
    JS

    attr_reader :browser_name, :last_snapshot

    def initialize(driver_factory: nil)
      @driver_factory = driver_factory || method(:default_driver)
      @driver = nil
      @dead = false
      @last_snapshot = []
    end

    def start(browser:, headless: true)
      quit if @driver
      @browser_name = browser
      @driver = @driver_factory.call(browser, headless)
      @dead = false
      @last_snapshot = []
    end

    def quit
      @driver&.quit
    rescue Selenium::WebDriver::Error::WebDriverError, *CONNECTION_ERRORS
      nil
    ensure
      @driver = nil
      @dead = false
    end

    def alive?
      !@driver.nil? && !@dead
    end

    def navigate(url)
      guard { @driver.navigate.to(url) }
    end

    def current_url = guard { @driver.current_url }
    def title = guard { @driver.title }

    def find(locator)
      guard do
        strategy, value = locator
        @driver.find_element(strategy.to_sym => value)
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      raise ElementNotFoundError.new(locator, suggestions_for(locator))
    end

    def click(locator)
      element = find(locator)
      metadata = guard { element_metadata(element) }
      metadata[:unique] = capybara_uniqueness(:click, metadata)
      guard { element.click }
      metadata
    end

    def type(locator, text, clear: false)
      element = find(locator)
      metadata = guard { element_metadata(element) }
      metadata[:unique] = capybara_uniqueness(:field, metadata)
      guard do
        element.clear if clear
        element.send_keys(text)
      end
      metadata
    end

    # Whether the Capybara idiomatic locator for this element (link/button text,
    # or a field's fill_in key) matches exactly one element. nil when the element
    # would not use an idiomatic locator anyway (renderer falls back regardless).
    def capybara_uniqueness(kind, metadata)
      count_kind, key = uniqueness_target(kind, metadata)
      return nil if key.nil?

      count = guard { @driver.execute_script(UNIQUENESS_JS, count_kind, key) }
      count == 1
    rescue Selenium::WebDriver::Error::WebDriverError
      nil
    end

    WAIT_CONDITIONS = %w[visible present gone].freeze

    def select_option(locator, text: nil, value: nil)
      text = nil if text == ""
      value = nil if value == ""
      raise ArgumentError, "provide text or value to select" if text.nil? && value.nil?

      element = find(locator)
      metadata = guard { element_metadata(element) }
      metadata[:unique] = capybara_uniqueness(:field, metadata)
      by, chosen = text.nil? ? [:value, value] : [:text, text]
      select = guard { Selenium::WebDriver::Support::Select.new(element) }
      begin
        guard { select.select_by(by, chosen) }
      rescue Selenium::WebDriver::Error::NoSuchElementError
        raise OptionNotFoundError.new(by, chosen, available_options(select, by))
      end
      [metadata, by, chosen]
    end

    def uniqueness_target(kind, metadata)
      if kind == :field
        key = metadata[:name] || metadata[:id]
        return [nil, nil] if key.nil?

        ["field", key]
      else # :click
        text = metadata[:text].to_s
        return [nil, nil] if text.empty?

        return ["link", text] if metadata[:tag] == "a"
        return ["button", text] if button_metadata?(metadata)

        [nil, nil]
      end
    end

    def button_metadata?(metadata)
      metadata[:tag] == "button" ||
        (metadata[:tag] == "input" && %w[submit button image].include?(metadata[:type].to_s))
    end

    def available_options(select, by)
      guard { select.options.map { |o| by == :value ? o.attribute("value") : o.text } }
    rescue Selenium::WebDriver::Error::WebDriverError
      []
    end

    def screenshot_base64 = guard { @driver.screenshot_as(:base64) }
    def execute_script(script) = guard { @driver.execute_script(script) }

    # Named wait_for (not wait_for?) per the brief's public interface; it returns true or raises.
    def wait_for(locator, condition:, timeout: DEFAULT_TIMEOUT) # rubocop:disable Naming/PredicateMethod
      raise ArgumentError, "unknown wait condition: #{condition}" unless WAIT_CONDITIONS.include?(condition)

      strategy, value = locator
      by = { strategy.to_sym => value }
      guard do
        Selenium::WebDriver::Wait.new(timeout: timeout).until do
          case condition
          when "visible" then @driver.find_elements(**by).any?(&:displayed?)
          when "present" then @driver.find_elements(**by).any?
          when "gone" then @driver.find_elements(**by).empty?
          end
        end
      end
      true
    end

    def snapshot
      # Compute both, then assign together, so a failure reading the URL never
      # leaves @last_snapshot updated against a stale @last_snapshot_url.
      entries = guard { @driver.execute_script(SNAPSHOT_JS) } || []
      url = guard { @driver.current_url }
      @last_snapshot = entries
      @last_snapshot_url = url
      entries
    end

    def element_metadata(element)
      {
        tag: element.tag_name,
        text: element.text.to_s.strip[0, 60],
        id: presence(element.attribute("id")),
        name: presence(element.attribute("name")),
        type: presence(element.attribute("type"))
      }
    end

    def password_field?(metadata)
      metadata[:type] == "password"
    end

    # Suggestions come from the last snapshot; after a navigation they would describe
    # the previous page, so they are only offered while the URL still matches.
    def suggestions_for(locator)
      return [] if @last_snapshot.empty? || snapshot_stale?

      _, value = locator
      needle = value.to_s.downcase
      scored = @last_snapshot.select do |entry|
        haystack = [entry["id"], entry["name"], entry["text"]].compact.join(" ").downcase
        haystack.include?(needle)
      end
      pool = scored.empty? ? @last_snapshot.first(3) : scored.first(3)
      pool.map { |e| describe_entry(e) }
    end

    private

    def snapshot_stale?
      @last_snapshot_url != @driver.current_url
    rescue Selenium::WebDriver::Error::WebDriverError, *CONNECTION_ERRORS
      true
    end

    def presence(str)
      str.nil? || str.empty? ? nil : str
    end

    def describe_entry(entry)
      locator = if entry["id"] then "id=#{entry['id']}"
                elsif entry["name"] then "name=#{entry['name']}"
                else "css=#{entry['tag']}"
                end
      %(#{entry['tag']} "#{entry['text']}" [#{locator}])
    end

    def guard
      raise SessionNotStartedError if @driver.nil?
      raise SessionDeadError if @dead

      yield
    rescue Selenium::WebDriver::Error::InvalidSessionIdError, Timeout::Error, *CONNECTION_ERRORS
      @dead = true
      raise SessionDeadError
    end

    def default_driver(browser, headless)
      raise ArgumentError, "unsupported browser: #{browser}" unless BROWSERS.include?(browser.to_s)

      options = Selenium::WebDriver::Options.send(browser)
      options.add_argument(HEADLESS_FLAGS[browser]) if headless && HEADLESS_FLAGS.key?(browser)
      Selenium::WebDriver.for(browser.to_sym, options: options)
    end
  end
end
