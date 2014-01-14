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
      t.boolean :active
      t.integer :posts_count
      t.timestamps
    end

    create_table 'posts' do |t|
      t.string :title
      t.integer :user_id
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

  allow_scopes :active
end

class Post < ActiveRecord::Base
  scope :published, -> { where(published: true) }
  has_many :comments

  allow_scopes :published
end

class Comment < ActiveRecord::Base
  scope :anonymous, -> { where %("author" IS NULL) }

  allow_scopes :anonymous
end
