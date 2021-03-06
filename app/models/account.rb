class Account < ActiveRecord::Base
  include PublicActivity::Common
  include Account::Couponable
  include Account::Payg

  acts_as_paranoid

  belongs_to :user
  has_many :invoices, dependent: :destroy
  has_many :credit_notes, dependent: :destroy
  has_many :payment_receipts, dependent: :destroy
  has_many :billing_cards, dependent: :destroy
  has_many :server_hourly_transactions, dependent: :destroy

  before_create :set_invoice_start_day
  before_create :create_payment_gateway_user

  validates :vat_number, length: { maximum: 20 }, if: lambda { respond_to? :vat_number }

  HOURS_MAX = 672
  RISKY_CARDS_ALLOWED = 3
  COUPON_LIMIT_MONTHS = 6.months

  scope :invoice_day, lambda { |date| where(invoice_day: date.day) }

  def hours_till_next_invoice(from_time=Time.now, today=Time.now)
    due_date = next_invoice_due(today)
    ((due_date - from_time) / 1.hour).ceil.abs
  end

  def hours_since_past_invoice
    due_date = past_invoice_due
    ((Time.now - due_date) / 1.hour).ceil.abs
  end

  def next_invoice_due(today=Time.now)
    # Calculate to 1am of the next invoice date
    invoice_date = next_invoice_date(today)
    Time.new(invoice_date.year, invoice_date.month, invoice_date.day, 1, 0, 0, '+00:00')
  end

  def past_invoice_due(today=Time.now)
    # Calculate to 1am of the past invoice date
    invoice_date = past_invoice_date(today)
    Time.new(invoice_date.year, invoice_date.month, invoice_date.day, 1, 0, 0, '+00:00')
  end

  def next_invoice_date(today=Time.now)
    # Rules for calculating the next invoice date:
    # - If the invoice day is today and it's before 1am, return today
    # - If the invoice day is today but it's past 1am, return next month
    # - If the invoice day for this month has passed, return next month also
    # - If the invoice day has not passed, just return the day for this month

    if today.day == invoice_day && today.hour < 1
      return today
    elsif today.day == invoice_day || today.day > invoice_day
      return today.next_month.change(day: invoice_day)
    else
      return today.change(day: invoice_day)
    end
  end

  def past_invoice_date(today=Time.now)
    # Rules for calculating the past invoice date:
    # - If the invoice day is today and it's before 1am, return the past date
    # - If the invoice day has not passed, return the past date
    # - If the invoice day is today but it's past 1am, return today
    # - If the invoice day for this month has passed, return this month

    if today.day == invoice_day && today.hour >= 1
      return today
    elsif today.day == invoice_day || invoice_day > today.day
      return today.last_month.change(day: invoice_day)
    else
      return today.change(day: invoice_day)
    end
  end

  def past_invoice_date_past_months(months = 1.month)
    past_invoice_date - months
  end

  def calculate_risky_card(result)
    case result
    when :rejected
      update!(risky_cards_remaining: risky_cards_remaining - 1)
    else
      update!(risky_cards_remaining: RISKY_CARDS_ALLOWED)
    end
  end

  def vat_exempt?
    if Account.in_gb?(billing_country)
      false
    elsif Account.in_eu?(billing_country)
      vat_number.present? ? true : false
    else
      true
    end
  end

  def tax_code
    if Account.in_gb?(billing_country)
      'GB-O-STD'
    elsif Account.in_eu?(billing_country)
      vat_number.present? ? 'GB-O-EUS' :  'GB-O-STD'
    else
      'GB-O-EXM'
    end
  end

  def billing_country
    if primary_billing_card.present?
      primary_billing_card.country
    else
      nil
    end
  end

  def billing_address
    primary_card = primary_billing_card

    if primary_card.present?
      {
        address1: primary_card.address1,
        address2: primary_card.address2,
        city:     primary_card.city,
        region:   primary_card.region,
        postal:   primary_card.postal,
        country:  primary_card.country
      }
    else
      nil
    end
  end

  def primary_billing_card
    cards = billing_cards.processable
    return (cards.find(&:primary?) || cards.first) if cards.present?
    nil
  end

  def remaining_invoice_balance
    invoices.to_a.sum(&:remaining_cost)
  end

  def remaining_credit_balance
    credit_notes.to_a.sum(&:remaining_cost)
  end

  def remaining_balance
    remaining_invoice_balance - remaining_credit_balance
  end

  def self.in_gb?(code)
    code == 'GB'
  end

  def self.in_eu?(code)
    %w(AT BE BG HR CY CZ DK EE FI FR DE EL HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE).include?(code)
  end

  private

  def set_invoice_start_day
    date = Account.billing_date
    self.invoice_start ||= date
    self.invoice_day   ||= date.day
  end

  def self.billing_date
    today = Date.today
    today = today.at_beginning_of_month.next_month if today.day > 28
    today
  end

  def create_payment_gateway_user
    self.gateway_id ||= Payments.new.create_customer(user)
  end
end
