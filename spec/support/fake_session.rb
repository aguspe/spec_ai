# frozen_string_literal: true

class FakeSession
  attr_reader :calls
  attr_accessor :alive, :raise_on_next, :unique

  def initialize
    @calls = []
    @alive = false
    @raise_on_next = nil
    @last_snapshot = []
    @unique = true
  end

  def check!(name)
    @calls << name
    return unless @raise_on_next

    err = @raise_on_next
    @raise_on_next = nil
    raise err
  end

  def start(browser:, headless: true)
    check!(:start)
    @alive = true
    @browser = browser
    @headless = headless
  end

  def quit
    check!(:quit)
    @alive = false
  end

  def alive?
    @alive
  end

  def browser_name
    @browser
  end

  def navigate(_url)
    check!(:navigate)
  end

  def current_url
    check!(:current_url)
    "https://example.com/login"
  end

  def title
    check!(:title)
    "Example Login"
  end

  def metadata
    { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" }
  end

  def find(_locator)
    check!(:find)
    :element
  end

  def click(_locator)
    check!(:click)
    metadata.merge(unique: @unique)
  end

  # rubocop:disable Lint/UnusedMethodArgument
  def type(_locator, _text, clear: false)
    check!(:type)
    metadata.merge(tag: "input", type: "text", text: "", unique: @unique)
  end
  # rubocop:enable Lint/UnusedMethodArgument

  def select_option(_locator, text: nil, value: nil)
    check!(:select)
    [metadata.merge(unique: @unique), :text, text || value]
  end

  def screenshot_base64
    check!(:screenshot)
    "aGVsbG8="
  end

  def execute_script(_script)
    check!(:execute)
    "ok"
  end

  # rubocop:disable Naming/PredicateMethod, Lint/UnusedMethodArgument
  def wait_for(_locator, condition:, timeout: 10)
    check!(:wait)
    true
  end
  # rubocop:enable Naming/PredicateMethod, Lint/UnusedMethodArgument

  def snapshot
    check!(:snapshot)
    [{ "tag" => "button", "id" => "login-btn", "name" => nil, "type" => "submit",
       "text" => "Log in", "href" => nil }]
  end

  def password_field?(meta)
    meta[:type] == "password"
  end

  def element_metadata(_element)
    metadata
  end

  def suggestions_for(_locator)
    []
  end
end
