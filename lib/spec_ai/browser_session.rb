# frozen_string_literal: true

require "selenium-webdriver"

module SpecAI
  # Interface is fixed by the task brief (navigate/find/click/type/select_option/screenshot/
  # execute_script/wait_for/snapshot/element_metadata/suggestions_for all live on the session),
  # so this stays over Metrics/ClassLength rather than being split for its own sake.
  class BrowserSession # rubocop:disable Metrics/ClassLength
    STRATEGIES = %w[id css xpath name link_text].freeze
    DEFAULT_TIMEOUT = 10
    HEADLESS_FLAGS = { "chrome" => "--headless=new", "edge" => "--headless=new", "firefox" => "-headless" }.freeze

    SNAPSHOT_JS = <<~JS
      const sel = "a, button, input, select, textarea, [role=button], h1, h2, h3";
      return Array.from(document.querySelectorAll(sel)).slice(0, 100).map((el) => ({
        tag: el.tagName.toLowerCase(),
        id: el.id || null,
        name: el.getAttribute("name"),
        type: el.getAttribute("type"),
        text: (el.innerText || el.value || "").trim().slice(0, 60),
        href: el.getAttribute("href")
      }));
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
    rescue Selenium::WebDriver::Error::WebDriverError
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
      guard { element.click }
      metadata
    end

    def type(locator, text, clear: false)
      element = find(locator)
      metadata = guard { element_metadata(element) }
      guard do
        element.clear if clear
        element.send_keys(text)
      end
      metadata
    end

    def select_option(locator, text: nil, value: nil)
      element = find(locator)
      metadata = guard { element_metadata(element) }
      by, chosen = text ? [:text, text] : [:value, value]
      guard do
        select = Selenium::WebDriver::Support::Select.new(element)
        select.select_by(by, chosen)
      end
      [metadata, by, chosen]
    end

    def screenshot_base64 = guard { @driver.screenshot_as(:base64) }
    def execute_script(script) = guard { @driver.execute_script(script) }

    # Named wait_for (not wait_for?) per the brief's public interface; it returns true or raises.
    def wait_for(locator, condition:, timeout: DEFAULT_TIMEOUT) # rubocop:disable Naming/PredicateMethod
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
      @last_snapshot = guard { @driver.execute_script(SNAPSHOT_JS) } || []
      @last_snapshot_url = guard { @driver.current_url }
      @last_snapshot
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
    rescue Selenium::WebDriver::Error::WebDriverError, Errno::ECONNREFUSED
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
    rescue Selenium::WebDriver::Error::InvalidSessionIdError, Errno::ECONNREFUSED
      @dead = true
      raise SessionDeadError
    end

    def default_driver(browser, headless)
      options = Selenium::WebDriver::Options.send(browser)
      options.add_argument(HEADLESS_FLAGS[browser]) if headless && HEADLESS_FLAGS.key?(browser)
      Selenium::WebDriver.for(browser.to_sym, options: options)
    end
  end
end
