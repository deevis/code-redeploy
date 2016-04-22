# Web Redeploy

An embedded console for pulling code from github and redeploying your server environments.

Is configured to work with Puma and Devise (for Authentication) out-of-the-box.

Default views are styled using Bootstrap classes.



# Add to your Rails Application

Gemfile

`gem 'web_redeploy', github: 'deevis/web_redeploy' 




# Development

### Running locally

`bundle install`

`cd spec/dummy`

`rake db:create db:migrate`

`rails s`
