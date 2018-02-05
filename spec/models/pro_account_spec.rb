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

require 'spec_helper'
require 'stripe_mock'

describe ProAccount do

  before do
    StripeMock.start
  end

  after do
    StripeMock.stop
  end

  let(:stripe_helper) { StripeMock.create_test_helper }
  let(:plan) { stripe_helper.create_plan(id: 'pro', amount: 1000) }

  let(:customer) do
    Stripe::Customer.create(
      email: FactoryGirl.build(:user).email,
      source: stripe_helper.generate_card_token
    )
  end

  let(:subscription) do
    Stripe::Subscription.create(customer: customer, plan: plan.id)
  end

  describe 'validations' do

    it 'requires a user' do
      pro_account = FactoryGirl.build(:pro_account, user: nil)
      expect(pro_account).not_to be_valid
    end

  end

  describe 'create callbacks' do

    it 'creates Stripe customer and stores Stripe customer ID' do
      pro_account = FactoryGirl.build(:pro_account, stripe_customer_id: nil)
      expect(Stripe::Customer).to receive(:create).and_call_original
      pro_account.run_callbacks :create
      expect(pro_account.stripe_customer_id).to_not be_nil
    end

  end

  describe '#stripe_customer' do

    subject { pro_account.stripe_customer }

    context 'with invalid Stripe customer ID' do
      let(:pro_account) do
        FactoryGirl.create(:pro_account, stripe_customer_id: 'invalid_id')
      end

      it 'raises an error' do
        expect{ pro_account.stripe_customer }.
          to raise_error Stripe::InvalidRequestError
      end

    end

    context 'with valid Stripe customer ID' do
      let(:pro_account) do
        FactoryGirl.create(:pro_account, stripe_customer_id: customer.id)
      end

      it 'finds the Stripe::Customer linked to the ProAccount' do
        expect(pro_account.stripe_customer).to eq(customer)
      end

    end

  end

  describe '#active?' do
    let(:pro_account) do
      FactoryGirl.create(:pro_account, stripe_customer_id: customer.id)
    end

    subject { pro_account.active? }

    context 'when there is an active subscription' do
      before { subscription.save }
      it { is_expected.to eq true }
    end

    context 'when there is an expiring subscription' do
      before { subscription.delete(at_period_end: true) }
      it { is_expected.to eq true }
    end

    context 'when an existing subscription is cancelled' do
      before { subscription.delete }
      it { is_expected.to eq false }
    end

    context 'when there are no active subscriptions' do
      it { is_expected.to eq false }
    end

    context 'when there is no customer id' do
      before { pro_account.stripe_customer_id = nil }
      it { is_expected.to eq false }
    end

  end

  describe '#monthly_batches' do
    let(:pro_account) { FactoryGirl.create(:pro_account) }
    subject { pro_account.monthly_batches }

    context 'monthly_batch_limit has not been set' do
      it { is_expected.to eq 1 }
    end

    context 'monthly_batch_limit has been set' do
      before { pro_account.monthly_batch_limit = 42 }
      it { is_expected.to eq 42 }
    end

  end

  describe '#batches_remaining' do

    let(:pro_account) do
      account = FactoryGirl.create(:pro_account)
      AlaveteliFeatures.backend.enable(:pro_batch_access, account.user)
      account
    end

    before { allow(pro_account).to receive(:monthly_batches).and_return(1) }

    it 'returns the monthly batch limit if no batches have been made' do
      expect(pro_account.batches_remaining).to eq 1
    end

    it 'returns 0 if all the available batches have been used' do
      FactoryGirl.create(:info_request_batch, user: pro_account.user)
      expect(pro_account.batches_remaining).to eq 0
    end

    it 'returns 0 if more than the available batches have been used' do
      FactoryGirl.create(:info_request_batch, user: pro_account.user)
      FactoryGirl.create(:info_request_batch, user: pro_account.user)
      expect(pro_account.batches_remaining).to eq 0
    end

    it 'returns 0 if the user does not have the pro_batch_access feature flag' do
      AlaveteliFeatures.backend.disable(:pro_batch_access, pro_account.user)
      expect(pro_account.batches_remaining).to eq 0
    end

  end

  describe '#update_email_address' do
    let(:user) { FactoryGirl.build(:user, email: 'bilbo@example.com') }
    let(:pro_account) { FactoryGirl.create(:pro_account, user: user) }

    before { allow(pro_account).to receive(:stripe_customer) { customer } }

    it 'update Stripe customer email address' do
      expect(customer.email).to_not eq user.email
      expect(customer).to receive(:save)
      pro_account.update_email_address
      expect(customer.email).to eq user.email
    end

  end

end
