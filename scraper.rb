#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

module Scraped
  class Scraper
    def initialize(h)
      @url, @klass = h.to_a.first
    end

    def store(method, index: %i[id], table: 'data', clobber: true, debug: ENV['MORPH_DEBUG'])
      data = scraper.send(method)
      data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if debug
      ScraperWiki.sqliteexecute('DROP TABLE %s' % table) rescue nil if clobber
      ScraperWiki.save_sqlite(index, data, table)
    end

    private

    attr_reader :url, :klass

    def scraper
      klass.new(response: Scraped::Request.new(url: url).response)
    end
  end
end

class MemberList < Scraped::HTML
  decorator WikidataIdsDecorator::Links

  field :members do
    member_rows.map do |tr|
      mem = fragment(tr => MemberRow).to_h
      mem.merge(party_id: faction_id(mem[:party]))
    end
  end

  def faction_id(str)
    faction_lookup[str.upcase]
  end

  private

  def members_table
    noko.xpath('//h2[span[@id="Mitglieder"]]/following-sibling::table[1]')
  end

  def member_rows
    members_table.xpath('.//tr[td]')
  end

  def faction_lookup
    @fl ||= noko.css('.thumbcaption ul li a').map { |a| [a.text.upcase, a.attr('wikidata')] }.to_h
  end
end

class MemberRow < Scraped::HTML
  field :id do
    member.attr('wikidata')
  end

  field :name do
    member.text.tidy
  end

  field :area_id do
    wahlkreis&.attr('wikidata')
  end

  field :area do
    wahlkreis&.text&.tidy
  end

  field :party do
    td[3].text.tidy
  end

  private

  def td
    noko.css('td')
  end

  def member
    td[1].css('a').first
  end

  def wahlkreis
    td[4].css('a').first
  end
end

url = 'https://de.wikipedia.org/wiki/Liste_der_Mitglieder_des_Abgeordnetenhauses_von_Berlin_(18._Wahlperiode)'
Scraped::Scraper.new(url => MemberList).store(:members, index: %i[name party])
