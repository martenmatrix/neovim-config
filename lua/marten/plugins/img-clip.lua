return {
  'HakonHarnes/img-clip.nvim',
  cmd = 'PasteImage',
  opts = {
    default = {
      embed_image_as_base64 = false,
      prompt_for_file_name = false,
      use_absolute_path = true,
      drag_and_drop = { insert_mode = true },
    },
    filetypes = {
      codecompanion = {
        prompt_for_file_name = false,
        template = '[Image]($FILE_PATH)',
        use_absolute_path = true,
      },
    },
  },
}
