#!/usr/bin/env ruby

# == Message structure
#
#  msg = {
#    :meta => {
#      :user => 'stefan',
#    },
#    :data => {
#      :msg => 'The message'
#    }
#  }
#
# == MQ
#
# Goal:
# The routing agent subscribes to a queue called 'input' (t.b.d). It then routes the message to an output queue
# based on a CouchDB view/document (t.b.d).
#
# The current implementation dispatches ALL messages to the 'jabber' output queue.
#
# The routing agent adds all the information to the message required for the output agent to work properly.
#
# == Requirements
#
#  [sudo] gem install tmm1-amqp
#  [sudo] gem install couchrest
#  [sudo] gem install json
#
# == Author
# Stefan Saasen
#
# == Copyright
# Copyright(c), 2009 Stefan Saasen coravy.com
require 'rubygems'
require 'mq'
require 'json'
require 'couchrest'
require 'logger'


DEFAULT_LOGGER = Logger.new(STDOUT)
DEFAULT_LOGGER.level = Logger::INFO

on_stop = lambda {
  AMQP.stop{ EM.stop }
  DEFAULT_LOGGER.info "Routing agent stopped..."
}

Signal.trap('INT', &on_stop)
Signal.trap('TERM', &on_stop)



module Phri
  module Agent
    module Routing
      SERVER = CouchRest.new
      SERVER.default_database = 'phri'

      class User < CouchRest::ExtendedDocument
        use_database SERVER.default_database

        property :user
        property :accounts

        timestamps!

        view_by :user
      end

      class Main
        def subscribe!
          DEFAULT_LOGGER.info "Subscribe routing agent"
          AMQP.start(:host => 'localhost') do
            amq = MQ.new
            amq.queue('input').subscribe do |msg|
              DEFAULT_LOGGER.debug "received msg: #{msg.inspect}"
              begin
                msg = JSON.parse(msg)

                user = User.by_user(:key => msg["meta"]["user"]).first
                DEFAULT_LOGGER.debug "user info from db: #{user}"

                # Add jabber specific information to the message
                msg["meta"]["destination"] = user["accounts"]["jabber"]

                # TODO Fetch routing information from CouchDB

                # Route msg to 'jabber' queue
                DEFAULT_LOGGER.info "Dispatching msg to Jabber queue"
                amq.queue('jabber').publish(msg.to_json)
              rescue => e
                DEFAULT_LOGGER.error "Error on receiving the folowing msg: #{msg.inspect} => #{e}"
              end
            end
          end
        end
      end

    end
  end
end

Phri::Agent::Routing::Main.new.subscribe!