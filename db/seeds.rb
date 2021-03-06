# Fetch available providers and templates from the OnApp installation
UpdateFederationResources.run

# Create an admin user
admin = User.find_or_create_by(email: 'admin@cloud.net') do |u|
  u.full_name = 'Cloud Admin'
  u.password = 'adminpassword'
  u.admin = true
end
admin.confirm! unless admin.confirmed?

# Get the available providers from the Onapp installation's federation
UpdateFederationResources.run
