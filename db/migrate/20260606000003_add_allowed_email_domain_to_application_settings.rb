class AddAllowedEmailDomainToApplicationSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :application_settings, :allowed_email_domain, :string
  end
end
