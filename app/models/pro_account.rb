# -*- encoding : utf-8 -*-
# == Schema Information
#
# Table name: pro_accounts
#
#  id                       :integer          not null, primary key
#  user_id                  :integer          not null
#  default_embargo_duration :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  stripe_customer_id       :string
#

class ProAccount < ActiveRecord::Base
  include AlaveteliFeatures::Helpers

  belongs_to :user,
             :inverse_of => :pro_account

  validates :user, presence: true

  before_create :set_stripe_customer_id

  def active?
    stripe_customer.present? && stripe_customer.subscriptions.any?
  end

  def stripe_customer
    @stripe_customer ||= stripe_customer!
  end

  def update_email_address
    return unless stripe_customer
    stripe_customer.email = user.email
    stripe_customer.save
  end

  def monthly_batches
    monthly_batch_limit || 1
  end

  def batches_remaining
    return 0 unless feature_enabled? :pro_batch_access, user
    remaining = monthly_batches - user.info_request_batches.
                                    where('created_at > ?', 1.month.ago).count
    ( remaining > -1 ) ? remaining : 0
  end

  private

  def set_stripe_customer_id
    self.stripe_customer_id ||= begin
      @stripe_customer = Stripe::Customer.create(email: user.email)
      stripe_customer.id
    end
  end

  def stripe_customer!
    Stripe::Customer.retrieve(stripe_customer_id) if stripe_customer_id
  end
end
