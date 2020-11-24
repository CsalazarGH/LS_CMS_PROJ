require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require 'yaml'
require 'bcrypt'

root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, 'secret'
end

helpers do
  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def no_file_name?(name)
  name.empty? || name == nil
end

def no_file_ext?(file_ext)
  !['.txt', '.md'].include?(file_ext)
end

def user_signed_in?
  session[:username]
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def duplicate_name(file_name)
  name, ext = file_name.split('.')
  
  (name + '-dup') + '.' + ext
end

def valid_credentials?(username, password)
  credentials = load_user_credentials['users']

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def username_taken?(username, data)
  data['users'].keys.map(&:downcase).include?(username.downcase)
end

def input_too_small?(input, size)
  input.strip.size < size
end

def bad_chars?(input)
  input.downcase.chars.any? {|char| !(/[0-9a-z]/.match(char)) }
end

def validate_username(username, data)
  if bad_chars?(username)
    session[:message] = "Username must be only letters or numbers"
    halt erb :signup
  elsif input_too_small?(username, 5)
    session[:message] = "Username must be at least 5 chars long (Letters and Numbers)"
    @attempted_name = username
    halt erb :signup
  elsif username_taken?(username, data)
    session[:message] = "#{username} is already taken"
    halt erb :signup
  end
end

def validate_password(password, username_input)
  if bad_chars?(password)
    session[:message] = "Password must be only letters or numbers"
    @attempted_name = username_input
    halt erb :signup
  elsif input_too_small?(password, 5)
    session[:message] = "Password must be at least 5 chars long"
    @attempted_name = username_input
    halt erb :signup
  end
end

def encrypt_password_input(password)
  BCrypt::Password.create(password).to_s
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :home
end

get '/new' do 
  require_signed_in_user
  erb :new
end

get '/users/signin' do
  erb :signin
end

post '/users/signin' do
  credentials = load_user_credentials
  username = params[:username]
  
  if valid_credentials?(username, params[:password])
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect '/'
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

post '/users/signout' do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get '/:file' do
   file_path = File.join(data_path, params[:file])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:file]} does not exist."
    redirect '/'
  end
end

get '/:file/edit' do
    require_signed_in_user

    file_path = File.join(data_path, params[:file])

    @filename = params[:file]
    @content = File.read(file_path)

    erb :edit
end

post '/new' do
  require_signed_in_user

  file_name = params[:file_name]
  file_ext = File.extname(file_name)

  if no_file_name?(file_name)
    session[:message] = "A name is required"
    status 422
    erb :new
  elsif no_file_ext?(file_ext)
    session[:message] = "Please use the .txt or .md extension when naming your file"
    status 422
    erb :new
  else
    file_path = File.join(data_path, file_name)

    File.write(file_path, '')
    session[:message] = "#{file_name} has been created"

    redirect '/'
  end
end

post '/:file' do
  require_signed_in_user

  file_path = File.join(data_path, params[:file])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:file]} has been updated"
  redirect "/"
end

post '/:file/duplicate' do
  require_signed_in_user

  original_file = File.join(data_path, params[:file])

  new_file = File.join(data_path, duplicate_name(params[:file]))
  File.write(new_file, File.read(original_file))

  session[:message] = "#{params[:file]} has been duplicated"

  redirect '/'
  
end

post '/:file/delete' do
  require_signed_in_user

  file_path = File.join(data_path, params[:file])

  File.delete(file_path)

  session[:message] = "#{params[:file]} has been deleted"
  redirect "/"
end

get '/users/signup' do
  erb :signup
end


post '/users/signup' do
  username_input = params[:username]
  password_input = params[:password]
  
  validate_username(username_input, load_user_credentials)
  
  validate_password(password_input, username_input)
  
  password = encrypt_password_input(password_input)
  user_info = YAML.load_file('users.yml')
  user_info['users'][username_input] = password

  File.open('users.yml', 'w') {|file| file << (user_info.to_yaml)}

  session[:message] = "Account #{username_input} created."
  redirect '/'
end
