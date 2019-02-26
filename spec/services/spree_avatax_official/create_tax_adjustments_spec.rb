require 'spec_helper'

describe SpreeAvataxOfficial::CreateTaxAdjustments do
  subject { described_class.call(order: order) }

  let(:usa_address) { create(:usa_address) }

  describe '#call' do
    context 'with external tax' do
      context 'with single line item order' do
        let(:order) { create(:avatax_order, line_items_count: 1, ship_address: usa_address) }
        let(:line_item) { order.line_items.first }
        let(:tax_adjustment) { line_item.adjustments.tax.first }

        it 'creates tax rates and tax adjustments' do
          result = nil

          VCR.use_cassette('spree_avatax_official/create_tax_adjustments/single_line_item') do
            result = subject

            order.updater.update
          end

          expect(result.success?).to eq true
          expect(order.total).to eq 10.8
          expect(order.additional_tax_total).to eq 0.8
          expect(line_item.reload.additional_tax_total).to eq 0.8
          expect(tax_adjustment.amount).to eq 0.8
          expect(tax_adjustment.source_type).to eq 'Spree::TaxRate'
        end
      end

      context 'with multiple line items with multiple quantity' do
        let(:order) { create(:avatax_order, ship_address: usa_address) }
        let(:first_line_item) { order.line_items.first }
        let(:second_line_item) { order.line_items.second }

        it 'creates tax rates and tax adjustments' do
          result = nil

          VCR.use_cassette('spree_avatax_official/create_tax_adjustments/multiple_line_items_multiple_quantity') do
            create(:line_item, id: 1, price: 10.0, quantity: 2, order: order)
            create(:line_item, id: 2, price: 10.0, quantity: 3, order: order)

            result = subject

            order.updater.update
          end

          expect(result.success?).to eq true
          expect(order.total).to eq 54.0
          expect(order.additional_tax_total).to eq 4.0
          expect(first_line_item.reload.additional_tax_total).to eq 1.6
          expect(second_line_item.reload.additional_tax_total).to eq 2.4
        end
      end

      context 'with promotion that adjusts line items' do
        let(:order) { create(:avatax_order, ship_address: usa_address) }
        let(:first_line_item) { order.line_items.first }
        let(:second_line_item) { order.line_items.second }
        let(:promotion) { create(:promotion, :with_line_item_adjustment, adjustment_rate: 10, code: 'promotion_code') }

        it 'creates tax rates and tax adjustments' do
          result = nil

          VCR.use_cassette('spree_avatax_official/create_tax_adjustments/line_item_adjustment_promotion') do
            create(:line_item, id: 1, price: 10.0, quantity: 4, order: order)
            create(:line_item, id: 2, price: 10.0, quantity: 3, order: order)

            order.updater.update
            order.coupon_code = promotion.code
            Spree::PromotionHandler::Coupon.new(order).apply

            result = subject

            order.updater.update
          end

          expect(result.success?).to eq true
          expect(order.total).to eq 54.0
          expect(order.additional_tax_total).to eq 4.0
          expect(first_line_item.reload.additional_tax_total).to eq 2.4
          expect(second_line_item.reload.additional_tax_total).to eq 1.6
        end
      end

      context 'with promotion that adjusts whole order' do
        let(:order) { create(:avatax_order, ship_address: usa_address) }
        let(:first_line_item) { order.line_items.first }
        let(:second_line_item) { order.line_items.second }
        let(:promotion) { create(:promotion, :avatax_with_order_adjustment, weighted_order_adjustment_amount: 20.0, code: 'promotion_code') }

        it 'creates tax rates and tax adjustments' do
          result = nil

          VCR.use_cassette('spree_avatax_official/create_tax_adjustments/order_adjustment_promotion') do
            create(:line_item, id: 1, price: 10.0, quantity: 4, order: order)
            create(:line_item, id: 2, price: 10.0, quantity: 3, order: order)

            order.reload.updater.update
            order.coupon_code = promotion.code
            Spree::PromotionHandler::Coupon.new(order).apply

            result = subject

            order.updater.update
          end

          expect(result.success?).to eq true
          expect(order.total).to eq 54.0
          expect(order.additional_tax_total).to eq 4.0
          expect(first_line_item.reload.additional_tax_total).to eq 2.28 # I would expect 2.4 but AvaTax applies discount proportionaly to price
          expect(second_line_item.reload.additional_tax_total).to eq 1.72 # I would expect 1.6 but AvaTax applies discount proportionaly to price
        end
      end
    end
  end
end