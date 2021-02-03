---
layout: post
title: "Batman.js and Devise"
date: 2014-07-21 09:08
categories:
  - Batman.js
  - Ruby on Rails
  - Devise
---

Using [batman.js](http://batmanjs.org) with [Devise](https://github.com/plataformatec/devise) is pretty straightforward.

<!-- more -->

It's also pretty cool-looking, because when you define `App.User.current`, all your view bindings are instantly updated to reflect the user's signed-in status!

You just have to consider three things:

- Make Devise communicate in JSON
- Make batman.js send Devise-friendly requests
- Keep your CSRF token up-to-date

## Make Devise Communicate in JSON

To make your Devise controllers accept and send JSON, register `:json` as a valid format. Do this by adding to `app/config/application.rb`:

```ruby
    config.to_prepare do
      DeviseController.respond_to :html, :json
    end
```

(From a [comment on plataformatec/devise](https://github.com/plataformatec/devise/issues/2209#issuecomment-12150223))

Now, all the provided Devise controllers will accept the JSON format.

## Make Batman.js Send Devise-friendly Requests

At time of writing (v0.16), the batman.js rails extra _only_ sends the CSRF token with `Batman.RailsStorage` storage operations. So, all your requests will be "disguised" as storage operations.

(These samples include code for updating the CSRF token which is described in detail below)

### Signing In / Signing Up

I made one form with two states: "signing in" or "signing up". I initialized a User to bind to the form:

```coffeescript
class Funzies.SessionsController extends Funzies.ApplicationController
  new: ->
    @set 'user', new Funzies.User
    @dialog()
```


In the form, `actionName` was either "Sign In" or "Create an Account":

```jade
.row
  .col-xs-12
    form data-event-submit='signIn'
      div.alert.alert-danger data-showif='user.errors.length'
        ul
          li data-foreach-e='user.errors' data-bind='e.fullMessage'
      .form-group
        label Email
        input.form-control type='text' data-bind='user.email'
      .form-group
        label Password
        input.form-control type='password' data-bind='user.password'
      .form-group data-showif='signingUp'
        label Password Confirmation
        input.form-control type='password' data-bind='user.password_confirmation'
      .form-group
        .row
          .col-sm-4
            input.btn.btn-primary type='submit' data-bind-value='actionName | append "!"'
          .col-sm-8
            a.pull-right data-event-click='signingUp | toggle' data-bind='otherActionName'
```

_(the `toggle` filter will be released in Batman.js 0.17)_

It turned out looking like this:

<p><img src="/assets/images/sign_in_form.png" width="500" /></p> <p><img src="/assets/images/sign_up_form.png" width="500" /></p>


Here's the handler for submitting that form. Notice that it handles _creating an account_ and _signing up_. This might have been stupid of me.

Notice the bit about initializing a new User -- it's because the `401` puts the user in "error" state (even with `@catchError`), which can't be cleared. This stinks and should be fixed in batman.js.

```coffeescript
  signIn: ->
    url = if @get('signingUp')
        "/users.json"
      else
        "/users/sign_in.json"
    @get('user').save {url}, (err, record, env) =>
      if newToken = env?.data?.csrf_token
        @updateCSRFToken(newToken)
      if err?
        if err instanceof Batman.StorageAdapter.UnauthorizedError
          @set 'user', new Funzies.User(record.toJSON())
          @get('user.errors').add("base", "Email/password don't match our records!")
        else
          console.log(err)
        return
      else
        record.unset('password')
        record.unset('password_confirmation')
        Funzies.User.set('current', record)
        @closeDialog()
```

### Signing Out

To send a `DELETE` request, we'll make a new user, then "destroy" it:

```coffeescript
  signOut: ->
    user = new Funzies.User
    user.url = "/users/sign_out.json"
    user.destroy (err, record, env) =>
      if newToken = env?.data?.csrf_token
        @updateCSRFToken(newToken)
      Funzies.User.unset('current')
```

Normally, destroying a not-yet-saved record throws an error. It doesn't throw an error in this case because the storage adapter doesn't check for presence of an ID. (Since we provide a URL, it doesn't need the ID for anything.)


## Keeping the CSRF Token Up-To-Date

When Rails changes the session, it also provides a new CSRF token for that session. This means that when your user signs in our out, Rails will expect a new CSRF token in the requests from that user. So, make devise send `csrf_token` when a user signs in or out.

Add to your Devise routes:

```ruby
  devise_for :users, controllers: {
    sessions: "users/sessions", # for sending CSRF tokens
  }
```

Then define the `users/sessions` controller. Put this in `app/controllers/users/sessions_controller.rb`:

```ruby
class Users::SessionsController < Devise::SessionsController
  respond_to :json

  def create
    resource = warden.authenticate!(
      :scope => resource_name,
      :recall => "#{controller_path}#failure"
      )
    sign_in_and_redirect(resource_name, resource)
  end

  def destroy
    sign_out(resource_name)
    # on sign-out, send back the CSRF token
    render json: {csrf_token: form_authenticity_token}
  end

  private
  def sign_in_and_redirect(resource_or_scope, resource=nil)
    scope = Devise::Mapping.find_scope!(resource_or_scope)
    resource ||= resource_or_scope
    if warden.user(scope) != resource
      sign_in(scope, resource)
    end
    # on sign-in, put the CSRF token in the JSON!
    return render json: current_user.as_json.merge({csrf_token: form_authenticity_token})
  end


  def failure
    return render :json => {:success => false, :errors => ["Login failed."]}
  end
end
```

Then, add a way for batman.js to update its `Batman.config.CSRF_TOKEN`. I put a function on my `SessionsController`:

```coffeescript
class Funzies.SessionsController
  updateCSRFToken: (token) ->
    Batman.config.CSRF_TOKEN = token
```

That's what I use in `signIn` and `signOut` above.
