require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'rspec/autorun'

require './lib/blondie'

ActiveRecord::Base.logger = Logger.new($stdout)

DATABASE_FILENAME = 'data.db'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: DATABASE_FILENAME
)

File.unlink DATABASE_FILENAME
unless ActiveRecord::Base.connection.tables.include?('schema_migrations')
  ActiveRecord::Migration.verbose = false
  ActiveRecord::Schema.define(version: 1) do
    create_table 'users' do |t|
      t.string :name
      t.string :login
      t.boolean :active
      t.integer :posts_count
      t.timestamps
    end

    create_table 'posts' do |t|
      t.string :title
      t.integer :user_id
      t.integer :favorite_count
      t.integer :share_count
      t.timestamps
    end

    create_table 'comments' do |t|
      t.string :author
    end
  end
end

class User < ActiveRecord::Base
  has_many :posts
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :id_in_list, lambda { |list| where(id: list.split(/[^\d]+/)) }
  scope :ascend_by_name_size, -> { order %(length("users"."name")) }

  # The joins in this scope is here for the sole purpose of testing
  scope :reverse_name_equals, lambda { |name| joins(:posts).where(name: name.reverse) }

  allow_scopes active: 0, id_in_list: 1, ascend_by_name_size: 0, reverse_name_equals: 1
end

class Post < ActiveRecord::Base
  scope :published, -> { where(published: true) }
  has_many :comments

  allow_scopes published: 0
end

class Comment < ActiveRecord::Base
  scope :anonymous, -> { where %("author" IS NULL) }

  allow_scopes anonymous: 0
end

class Helper

  include Blondie::FormHelper

  def form_tag(path, options)
    yield(self) if block_given?
  end

  def fields_for(object_alias, object)
  end

end
