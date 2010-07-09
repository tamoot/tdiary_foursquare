# -*- coding: utf-8 -*-                                                                                                                                      
#
# foursquare.rb - A simple foursquare badge for tDiary
#
# Copyright (C) 2010, tamoot <tamoot+tdiary@gmail.com>
# You can redistribute it and/or modify it under GPL2.
#

require 'pstore'
require 'timeout'
require 'net/http'
require 'rexml/document'

def foursquare_badge( options = {:badges => true, :mayor => true} )
	cache = ::Foursquare::Cache.new(foursquare_pstore)
	data  = cache.read
	interval_hour = @conf['foursquare.cache_refresh_interval'].to_i
	
	# cache refresh
	if Time::now - data[:updated_at] > interval_hour * 3600
		user   = @conf['foursquare.mail']
		pass   = @conf['foursquare.password']
		latest = ::Foursquare::BasicAuth.new(user, pass, options).update
		data   = cache.save(latest)
	end
	
	body = ''
	unless @cgi.mobile_agent?
		body =  %Q|<div class="foursquare-widget">\n|
		body << %Q|	<div class="foursquare-mayor">\n|
		body << %Q|		<span class="header">Mayor: </span><span class="digits">#{data[:mayor_count]}</span>\n|
		body << %Q|	</div>\n|
		body << %Q|	<div class="foursquare-badges">\n|
		body << %Q|		<span class="header">Badges: </span><span class="digits">#{data[:badge_count]}</span>\n|
		body << %Q|	</div>\n|
		body << %Q|	<div class="foursquare-last">\n|
		body << %Q|		<span class="header">Last: </span><span class="checkin-venue"><a href="http://foursquare.com/venue/#{data[:last_venue_id]}">#{data[:last_venue_name]}</a></span>\n|
		body << %Q|	</div>\n|
		body << %Q|</div>\n|
	end
	body
end


add_conf_proc( 'foursquare_user_info', 'Foursquare User Info' ) do
	if @mode == 'saveconf' then
		@conf['foursquare.mail']     = @cgi.params['foursquare.mail'][0]
		@conf['foursquare.password'] = @cgi.params['foursquare.password'][0]
		@conf['foursquare.cache_refresh_interval'] = @cgi.params['foursquare.cache_refresh_interval'][0]
	 end
	
	<<-HTML
	<h3 class="subtitle">Foursquare User Mail Address</h3>
	<p><input name="foursquare.mail" value="#{h @conf['foursquare.mail']}" size="70"></p>
	<h3 class="subtitle">Foursquare User Password</h3>
	<p><input type="password" name="foursquare.password" value="#{h @conf['foursquare.password']}" size="70"></p>
	<h3 class="subtitle">Cache refresh interval(hour)</h3>
	<p> 0: force refresh
	<p><input name="foursquare.cache_refresh_interval" value="#{h @conf['foursquare.cache_refresh_interval']}" size="30"></p>
	HTML
end


def foursquare_pstore
	cache_path = @conf.cache_path || "#{@conf.data_path}cache"
	plugin_cache_dir = "#{cache_path}/foursquare"
	Dir::mkdir(plugin_cache_dir) unless File::directory?(plugin_cache_dir)
	"#{plugin_cache_dir}/user.dat"
end


module ::Foursquare
	class Cache
		def initialize(path)
			@path = path
		end
		def save(data)
			latest = {}
			PStore.new(@path).transaction do |db|
				db[:cache] = data
				latest = db[:cache]
			end
			latest
		end
		def read
			cache = {}
			PStore.new(@path).transaction(true) do |db|
				cache = db[:cache]
			end
			cache || { :updated_at => Time.local(2010, 1, 1, 0, 0, 0) }
		end
	end
	
	class BasicAuth
		def initialize(mail, password, options)
			@mail     = mail
			@password = password
			@options  = options
		end
			
		# get foursquare info
		def update(cache = {})
			root = nil
			if cache[:uid].nil?
				uid = request.elements.to_a( '/user/id' ).first.text
				@options.merge!( :uid => uid )
			end
			root = request( to_query_params(@options) )
			latest_data = {
				:uid => root.elements.to_a( '/user/id' ).first.text,
				:mayor_count => root.elements.to_a( '/user/mayorcount' ).first.text,
				:badge_count => root.elements.each( '/user/badges/badge' ){}.size.to_s,
				:last_venue_id => root.elements.to_a( '/user/checkin/venue/id' ).first.text,
				:last_venue_name => root.elements.to_a( '/user/checkin/venue/name' ).first.text,
				:updated_at => Time::now
			}
			latest_data
		end
		
		private
		
		def request(options = {})
			res  = nil
			Net::HTTP.version_1_2
			user_info = Net::HTTP::Get.new( "/v1/user?" << to_query_params(options) )
			user_info.basic_auth( @mail, @password )
			
			begin
				timeout( 10 ) do 
					Net::HTTP.start('api.foursquare.com', 80) do |api|
						res = api.request(user_info)
						raise 'update failed' if res =~ /error/
						raise 'authentication failed' if res =~ /unauthorized/
					end
				end
			rescue TimeoutError => e
				raise e
			end
			REXML::Document.new(res.body).root
		end
		
		def to_query_params(options = {})
			options.collect { |key, value| "#{key}=#{value}" }.join('&')
		end
	end
end


# Local Variables:
# mode: ruby
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# End:
# vim: ts=3
