# By Erik Oliver
#
# License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
# (C) 2016 Richardson Oliver Law Group

require 'rubygems'
require 'net/http'
require 'open-uri'
require 'nokogiri'

class FetchFreshbooks

#public key and url
  attr_accessor :key, :url

#key and url are initialized
#these are used later in fetch_XML
  def initialize
    @key= 'myapikeyhere'
    @url= 'https://mysubdomain.freshbooks.com/api/2.1/xml-in'
  end

#invoice query that is made based on the pages
#this if function is called on later in fetch_XML
  def page_query(page)
  	query1 = <<-XML
  		<?xml version="1.0" encoding="utf-8"?>
  		<request method="invoice.list">
  		<page>#{page}</page>
  		<per_page>3</per_page>
  		</request>
  		XML
  end

#invoice query that is made based on date range and pages
#this if function is called on later in fetch_XML
  def date_query(from,page)
    <<-XML
  		<?xml version="1.0" encoding="utf-8"?>
  		<request method="invoice.list">
      <page>#{page}</page>
      <updated_from>#{from}</updated_from>
  		<per_page>100</per_page>
  		</request>
  		XML
  end

#deleted query that is made based on date range and pages
#function is called on later in fetch_XML
  def deleted_query(from,page)
    <<-XML
  		<?xml version="1.0" encoding="utf-8"?>
  		<request method="invoice.list">
      <page>#{page}</page>
      <updated_from>#{from}</updated_from>
  		<per_page>100</per_page>
      <folder>deleted</folder>
  		</request>
  		XML
  end
#project query that is made based on pages
#function is called on later in fetch_XML
  def project_query(page)
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <request method="project.list">
      <page>#{page}</page>
      <per_page>100</per_page>
      </request>
    XML
  end

#time entry query that is made based on pages
#function is called on later in fetch_XML

  def time_entry_query(page)
      <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <request method="time_entry.list">
      <page>#{page}</page>
      <per_page>100</per_page>
      </request>
      XML

  end

#staff query that is made based on pages
#function is called on later in fetch_XML

  def staff_query(page)
      <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <request method="staff.list">
      <page>#{page}</page>
      <per_page>100</per_page>
      </request>
      XML

  end

#contractor query that is made based on pages
#function is called on later in fetch_XML

  def contractor_query(page)
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <request method="contractor.list">
      <page>#{page}</page>
      <per_page>100</per_page>
      </request>
    XML
  end




# fetch_XML - takes as input a string to send an HTTP request to retrieve and return
#the body of the HTTP result. The URL of the endpoint and the API key are defined in
# the class initializer.
#
#Inputs: query string, e.g. see the contractor_query, staff_query, etc.
# methods for example of queries
#Output: body of HTTP result, e.g. raw XML text
  def fetch_XML(query)
    uri = URI.parse(url)
    req = Net::HTTP::Post.new(uri)
    req.body = query
    req.basic_auth(key,'X')
    res = Net::HTTP.start(uri.hostname, uri.port, :read_timeout => 5, :use_ssl => uri.scheme == 'https'){|http|
    	http.request(req)
      }

# debugging code to see the XML responses directly
#     f = File.new("sample_2.xml",'a')
#   	f.write(res.body)
#   	f.close()
    if (check_HTTP_request(res.body) == 'ok')
    	return res.body

    else
      puts 'HTTP request error'
      exit
    end
  end

  def check_HTTP_request(res)
    doc = Nokogiri::XML(res)
    status = doc.css("response").first["status"]
    return status
  end
end
