require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require 'yaml/store'
require "yaml"
require 'bcrypt'
require "pry"

configure do 
  enable :sessions
  set :session_secret, 'secret'
end

class PasswordDigester
  def self.encrypt(password)
    BCrypt::Password.create(password)
  end

  def self.check?(password, encrypted_password)
    BCrypt::Password.new(encrypted_password) == password
  end
end

def get_user_creds
    users = File.expand_path("../users.yml", __FILE__)
    YAML.load_file(users)
end

def user_signed_in?
  session.key?(:user)
end

def require_user_signin
  unless user_signed_in?
    session[:failure] = "You must be signed in to do that."
    redirect "/signin"
  end
end

def validate_username(user_list, entry)
  if user_list.key?(entry)
     session[:failure] = "This entry already exists. Please try another."
    status 422
  elsif entry.size == 0
    session[:failure] = "# Input must contain characters."
    status 422
  elsif !(1..100).cover? entry.strip.size
    session[:failure] = "# Input must be between 1 and 100 characters."
    status 422
  else
    false
  end
end

def validate_password(password)
  if password.size == 0
    session[:failure] = "Password must contain characters"
    status 422
     erb :registration
  elsif !(5..100).cover? password.strip.size
    session[:failure] = "Password must be between 5 and 100 characters."
    status 422
  else
    false
  end
end

get "/" do
  redirect "/signin"
end

get "/signin" do
  @title = "Voting App"
  redirect "/home" if session[:user] 
  erb :signin
end

post "/signin" do
  @title = "Voting App"
  users = get_user_creds
  username = params[:username]
  password = params[:password]
  if users.key?(username) && PasswordDigester.check?(password, users[username])
    session[:user] = username
    session[:success] = "Welcome!"
    redirect "/home"
  else
    session[:failure] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/signout" do
  session.delete(:user)
  session[:success] = "You have been signed out."
  redirect "/signin"
end

get "/register" do
  @title = "Create an Account"
  erb :registration
end

post "/register" do
  username = params[:username]
  password = params[:password]
  users = get_user_creds
  file = YAML::load_file('users.yml')
  if validate_username(users, username)
      erb :registration
  elsif validate_password(password)
      erb :registration
  else
    encrypted_password = PasswordDigester.encrypt(password)
    
    file[username] = encrypted_password.to_s
    File.open('users.yml', 'w') {|f| f.write file.to_yaml}
    session[:success] = "Your account has been created"
    redirect "/signin" 
  end
end

get '/home' do
  require_user_signin
  @title = 'Voting App'
  erb :index 
end

Choices = {
  'HAM' => 'Hamburger',
  'PIZ' => 'Pizza',
  'CUR' => 'Curry',
  'NOO' => 'Noodles'
}

post "/cast" do 
  require_user_signin

  @tracker = YAML::Store.new 'vote_tracker.yml'
  user = session[:user]
  vote_limit = 2
  vote_count = "#{session[:user]} votes"
  @tracker.transaction do
       @tracker[user] ||= {}
       @tracker[user][vote_count] ||= 0
    if @tracker[user][vote_count] < vote_limit
        @tracker[user][vote_count] += 1
        @title = 'Thanks for casting your vote!'
        @vote  = params['vote']
        @store = YAML::Store.new 'votes.yml'
        @store.transaction do
          @store['votes'] ||= {}
          @store['votes'][@vote] ||= 0
          @store['votes'][@vote] += 1
        end
    else
     session[:failure] = "This account has already voted!"
    end
  end
  erb :cast
end

get '/results' do
  @title = 'Current Results:'
  @store = YAML::Store.new 'votes.yml'
  @votes = @store.transaction { @store['votes'] }
  erb :results
end