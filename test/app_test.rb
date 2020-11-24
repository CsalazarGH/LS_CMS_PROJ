ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../CMS.rb"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end


  def test_index
    file_names = ['about.md', 'changes.txt', 'history.txt']
    file_names.each {|name| create_document(name)}
    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['content-type']

    file_names.each {|name| assert_includes last_response.body, name}
  end

  def test_history_page
    create_document 'history.txt', '2013 - Ruby 2.1 released.'
    get '/history.txt'

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, '2013 - Ruby 2.1 released.'
  end

  def test_bad_file_input
    get '/badinput.txt'
    assert_equal 302, last_response.status
    assert_equal "badinput.txt does not exist.", session[:message]

    get last_response["location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "badinput.txt does not exist."

    get '/'
    assert_equal 200, last_response.status
    assert_nil session[:message]
  end

  def test_viewing_markdown_document
    create_document 'about.md', '# Ruby is...'

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['content-type']
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing_links
    create_document 'about.md'

    get '/'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Edit'
  end

  def test_editing_document
    create_document 'changes.txt'

    get '/changes.txt/edit', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_updated_document
    post '/changes.txt', {content: 'new content'}, admin_session
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated", session[:message]

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'new content'
  end

  def test_new_document
    get '/', {}, admin_session
    assert_includes last_response.body, 'New Document'

    get '/new'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<form method="post" action="/new">'
    assert_includes last_response.body, 'Add a new document:'

    post '/new', file_name: 'new_file.txt'
    assert_equal 302, last_response.status
    assert_equal 'new_file.txt has been created', session[:message]

    get last_response["Location"]
    assert_includes last_response.body, 'new_file.txt has been created'

    get '/'
    assert_nil session[:message]
  end

  def test_new_document_bad_input
    post '/new', {file_name: 'new_file'}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Please use the .txt or .md extension when naming your file'

    post '/new', file_name: ''
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A name is required'
  end

  def test_delete_feature
    file_names = ['about.md', 'changes.txt', 'history.txt']
    file_names.each {|name| create_document(name)}

    get '/', {}, admin_session
    assert_includes last_response.body, '<form class="inline" method="post" action="/about.md/delete">'

    post '/about.md/delete'
    assert_equal 302, last_response.status
    assert_equal "about.md has been deleted", session[:message]

    get last_response["Location"]
    refute_includes last_response.body, "<a href='/about.md'>about.md</a>"

    get '/'
    assert_nil session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "guest", password: "shhhh"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_signout
    get '/', {}, {"rack.session" => { username: "admin" } }
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]

    get last_response['location']
    assert_nil session[:username]

    assert_includes last_response.body, "Sign In"
  end

  def test_duplicate_file
    create_document 'about.md', '#Ruby is...'
    get '/', {}, {"rack.session" => { username: "admin" } }

    post '/about.md/duplicate'
    assert_equal "about.md has been duplicated", session[:message]

    get last_response["location"]
    assert_includes last_response.body, "about-dup.md"

    get '/about-dup.md'
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end
end