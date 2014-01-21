# Blondie

Blondie removes the hassle of creating complex search pages for your database records.

It is inspired by https://github.com/binarylogic/searchlogic (with a few differences though) and runs with Rails 4.

## Liminal warning

This gem is currently in alpha stage. Not all the features are yet implemented and it is not recommended for production usage.

### What is missing?

Currently, the following things are missing:

* Can't search on polymorphic associations.
* Most condition operator (greater than, lower than, not like, ends with, blank, does not equal, etc.) aren't implemented.

## Install

As usual, add it to your Gemfile:

    gem 'blondie', :git => 'git@github.com:Ghrind/blondie.git', :branch => 'master'

If you want to use the Rails helpers, you should add the following to you ApplicationHelper module:

    include Blondie::FormHelper

## Usage

### Search using conditions on columns

Basically, what you can do is searching on your model's columns.

    User.search(name_equals: 'David').result

Is the equivalent of:

    User.where(name: 'David')

But blondie adds a little magic.

For example:

    search_term = 'Dav'
    User.search(name_like: term).result

Is the equivalent of:

    search_term = 'Dav'
    User.where("`users`.`name` LIKE ?", "%#{search_term}%")

There are currently no other operator, but more are to come.

Of course, you can provide multiple conditions.
The following will search for all users with the name Johnson and the firstname like Dav:

    User.search(lastname_equals: 'Johnson', firstname_like: 'Dav').result

### Using scopes

You may want to add your own conditions to your search.

You can achieve this by allowing some scopes of your class to be used as conditions.

As scopes may need arguments, you must also specify the arity of your scope to Blondie.

    class User
      scope :active_writers, -> { where("activated_at IS NOT NULL").where("posts_count > 0") }
      scope :admins, -> { where(admin: true) }
      scope :active_since, -> (number) { where("activated_at >= ?", number.days.ago) }

      allow_scopes active_writers: 0, active_since: 1
    end

    User.search(active_writers: '1').result # Equivalent to User.active_writers
    User.search(active_since: 7).result     # Equivalent to User.active_since(7)
    User.search(admins: '1').result         # The condition will not be recognized

When a scope takes no arguments, passing any other value than '1' will just ignore the condition.

    User.search(active_writers: true).result # Condition will be ignored

### Condition modifiers (any, all)

All the basic operators (like, equals, ...) can be modified by \_any and \_all.

    User.search(name_like_all: ['jon', 'han']) # Will return Jonathan but not Jonas or Hans 
    User.search(name_like_any: ['jon', 'han']) # Will return Jonathan, Jonas and Hans 

### Combining conditions with 'OR'

You can combine all conditions by using '\_or\_' in your condition.

    User.search(name_like_or_login_equals: 'dav').result

Or if the operator is the same for every conditions:

    User.search(name_or_login_like: 'dav').result

This can be chained multiple times:

    User.search(firstname_or_lastname_or_login_like: 'dav')

### Conditions on associated classes

Lets say you have the following:

    class Post
    end

    class User
      has_many :posts
    end

You can now use the following syntax for your conditions:

    User.search(posts_content_like: 'ruby').result

This will automatically join the posts table and retrieve those which content is like 'ruby'.

Of course, you can use scopes, '\_any', '\_all', '\_or\_' on associations.

### Adding conditions on the fly

Once you've created your search instance, you can easily change the conditions like this:

    search = User.search(name_like: 'dav')

    search.posts_count = 0      # Adds a new condition on posts count
    search.active_writers = '1' # Adds the active_writers scope
    search.name_like = 'ben'    # Searches for 'ben' instead of 'dav'

    search.posts_content_like_any = %w(ruby rails) # Adds condition on posts content

    search.result # Actually parses the conditions
                  # and returns the object on which you can call .first, .all, .paginate, ...

### Order your search

You can easily order your search using the following syntax:

    User.search(order: 'ascend_by_name').result  # Order by name ascending
    User.search(order: 'descend_by_name').result # Order by name descending

Or, if you already have a search instance :

    search.order = 'ascend_by_name'

## Real life example

Let's see how to use Blondie to create rich search forms easily.

In your controller (using https://github.com/mislav/will_paginate)

    def index
      # Use provided search query or a default one
      @search = User.search(params[:q] || {active_writers: '1'})

      # Use provided order or a default one
      @search.order ||= :descend_by_posts_count

      # Actually do the query
      @users = @search.result.paginate(page: params[:page])
    end

In your model

    allowed_scopes active_writers: 0, ... # Whatever scopes you want to search for

In your view (this is HAML)

    = search_form_for @search do |f|
      = f.label :name_like
      = f.text_field :name_like

      = f.label :posts_content_like
      = f.text_field :posts_content_like

      %label{ for: 'q_active_writers' }
        = f.check_box :active_writers
        Active writers

      = f.label :order
      = f.select :order, %w(ascend_by_posts_count descend_by_posts_count).map{|i|[i.humanize, i]}

      = f.submit 'Search'

Don't forget to include Blondie::FormHelper in your ApplicationHelper.

### Safe search

Passing the conditions directly from GET or POST parameters opens the search conditions to be forged and to contain syntax errors.

Instead of crashing when detecting syntax errors in conditions, Blondie will by default return an empty collection (by calling #none on your class).

You can change this setting with the following code:

    Blondie.safe_search = false

When developping, you'll probably want it to raise an error instead. You can use the following initializer to switch behavior between dev and prod.

    # config/initializers/blondie.rb

    Blondie.safe_search = !Rails.env.development?
