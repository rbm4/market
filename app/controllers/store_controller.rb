class StoreController < ApplicationController
    
    def store
        @products = Shoppe::Product.root.ordered.includes(:product_categories, :variants)
        @products = @products.group_by(&:product_category)
    end

    def show
        @product = Shoppe::Product.root.find_by_permalink(params[:permalink])
    end
    def buy
         @product = Shoppe::Product.root.find_by_permalink!(params[:permalink])
         current_order.order_items.add_item(@product, 1)
         @messages = "Product has been added successfuly!"
         redirect_to product_path(@product.permalink)
    end
end