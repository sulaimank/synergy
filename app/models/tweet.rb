require 'twitter'

class Tweet < ActiveRecord::Base
  # Tweet cannot exceed 140 characters
  validates :message, length: { maximum: 140 }

  # When we post a tweet, we set the tweet_id to this special value.
  # When we retrieve a list of all tweets, we update the tweet_id with
  # the Tweet id that Twitter provides.
  TWEET_TEMP_TWEET_ID = 999

  def self.send_tweet_and_save(tweet)
    begin
      self.get_client.update tweet.message.encode
    rescue Exception => e
      logger.debug e.message
      logger.debug e.backtrace.inspect

      return
    end

    # We are persisting the Tweet that the user created with a special
    # id.  This will help when there are error conditions with sending
    # the tweet.  In future, we could provide for a retry mechanism.
    tweet.tweet_id = TWEET_TEMP_TWEET_ID
    tweet.save
  end

  def self.get_client
    @@client ||= Twitter::REST::Client.new do |config|
      config.consumer_key =         ENV["OMNIAUTH_PROVIDER_KEY"]
      config.consumer_secret =      ENV["OMNIAUTH_PROVIDER_SECRET"]
      config.access_token =         ENV["OMNIAUTH_ACCESS_TOKEN"]
      config.access_token_secret =  ENV["OMNIAUTH_ACCESS_TOKEN_SECRET"]
    end

    @@client
  end

  def self.retrieve_all_tweets
    username = User.first.name || ENV['OMNIAUTH_DEFAULT_USERNAME']

    begin
      tweets = self.get_client.user_timeline(username)
    rescue Exception => e
      logger.debug e.message
      logger.debug e.backtrace.inspect

      return nil
    end

    # We now want to persist tweet if it does not exist in database
    tweets.each do |tweet|
      twitter_tweet = Tweet.find_by(:tweet_id => tweet.id)
      if (twitter_tweet.nil?)
        # See if there is a db record with invalid tweet_id
        a_tweet = Tweet.find_by(:message => tweet.full_text, :tweet_id => TWEET_TEMP_TWEET_ID)
        if (a_tweet.nil?)
          a_tweet = Tweet.new(:message => tweet.full_text, :tweet_id => tweet.id)
        else
          # Update the default tweet id with the one Twitter generates.
          a_tweet.update_attributes(:tweet_id => tweet.id)
        end

        a_tweet.save
      end
    end

    # Detect Tweets that failed to get posted by Twitter.
    # TODO: Limit the retries
    bad_tweets = Tweet.find_by(:tweet_id => TWEET_TEMP_TWEET_ID)
    unless bad_tweets.nil?
      bad_tweets.each do |tweet|
        logger.debug "Failed to post Tweet with message #{tweet.message}"
        send_tweet_and_save tweet
      end
    end

    tweets
  end
end
