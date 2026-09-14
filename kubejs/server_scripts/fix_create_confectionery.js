// Create Confectionery ships these four recipe ids broken, so the pack removes
// them instead of carrying a patched copy of the mod. Not cruft: delete this
// file and the broken recipes come back. Re-check on any Create Confectionery
// update, and drop the file once upstream has fixed them.
ServerEvents.recipes(event => {
  event.remove({ id: 'create_confectionery:black_chocolate_recipe_6' })
  event.remove({ id: 'create_confectionery:white_chocolate_recipe_6' })
  event.remove({ id: 'create_confectionery:chocolate_recipe_6' })
  event.remove({ id: 'create_confectionery:ruby_chocolate_recipe_6' })
})