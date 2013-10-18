require 'rubygems'
require 'ruby-saml'
require "net/http"
require "uri"
require "json"
require_relative 'session_helper'

class ActionController::Base
  include OktaSaml::SessionHelper

  def okta_authenticate!
    session[:redirect_url] = params[:app_referer] || "#{request.protocol}#{request.host_with_port}#{request.fullpath}"
    auth_code = params[:auth_code]

    # if no auth_code from propsol, auth using okta
    if auth_code.blank?
      redirect_to saml_init_path unless signed_in?

    else
      ps_user_id = get_user_id(auth_code)
      email = get_cr3_email(ps_user_id)

      if email.present?
        # They have auth_code and mapping already exists (since email present)
        # so log them in.
        sign_in(OktaUser.new({:email => email}))

      else # no mapping exists
        if signed_in? # if already signed into okta, but does have
                      # auth_code create the mapping.
          create_ps_to_cr3_mapping(ps_user_id, current_user.email)

        else # since not signed into okta, send them to okta login.
          redirect_to saml_init_path
        end
      end
    end
  end

  def okta_logout
    redirect_to saml_logout_path
  end

  def create_ps_to_cr3_mapping(ps_user_id, email)
    randr_uri = randr_uri("/portalsvc/propsol/add-user-mapping")
    params = {"ps-user-id" => ps_user_id, "cr3-email" email}
    res = http_get(randr_uri, params)
    res["result"]
  end

  def get_cr3_email(ps_user_id)
    randr_uri = randr_uri("/portalsvc/propsol/get-cr3-user")
    params = {"ps-user-id" => ps_user_id}  # { "email": "foo@bar.com" or "" }
    res = http_get(randr_uri, params)
    res["email"]
  end

  def get_user_id(auth_code)
    randr_uri = randr_uri("/portalsvc/propsol/get-ps-user-id")
    params = {"auth-code" => auth_code}
    res = http_get(randr_uri, params) # { "user-id": "-1" }
    res["user-id"]
  end

  def http_get(uri, params)
    uri = URI.parse(uri)
    uri.query = URI.encode_www_form(params)
    res = Net::HTTP.get_response(uri)
    JSON.parse(res.body)
  end

  def randr_uri(path)
    uri = Rails.application.config.randr_service + path
  end
end

module OktaSaml
  class Engine < Rails::Engine
    def initialize
      require "okta_saml/constants"
      Rails.application.config.session_store :active_record_store, :key => '_my_key', :domain=> :all
      add_engine_helpers
    end

    def add_engine_helpers
      ActiveSupport.on_load :action_controller do
        helper OktaSaml::SessionHelper
      end
    end
  end
end
