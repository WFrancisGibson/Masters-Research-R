-- guide_tables.lua
-- pandoc Lua filter (pandoc >= 3.0) for Word reports in the format of
-- project_folder_guide.docx; used together with guide_reference.docx.
--   * every table gets the table style "Light Grid Accent 1"
--   * the cell font is 10 pt (as in the guide) and drops to 9, 8, 7 or 6 pt
--     only when the table would not fit the page width
--   * Word sizes the columns itself (autofit); numbers and short labels are
--     kept on one line, header cells and long text cells may wrap
--   * the first column is bold (the guide's table has firstColumn = 1)
--   * a small gap follows every table
--   * tight lists keep the 11 pt body font
--
-- optional settings in the YAML header of the Rmd:
--   guide-tables:
--     text-width: 9.42         usable page width in inches
--     first-column-bold: true
-- one table can be forced to a size by a fenced Div around its chunk:
--   ::: {table-font-size="7"}
--   ...
--   :::

local text_width = 9.42       -- landscape Letter, 2 cm margins: 9.425 in
local first_column_bold = true
local max_text_chars = 30     -- longer text cells may wrap
local safety = 1.03           -- margin on the estimated text widths
local nbsp = '\u{00A0}'

-- candidate layouts, tried in this order; pad = left + right cell margin
-- of the table style (in): 2 x 108 twips and 2 x 43 twips
local tiers = {
  { size = 10, style = 'LightGrid-Accent1',       pad = 0.152 },
  { size = 10, style = 'LightGrid-Accent1-Tight', pad = 0.062 },
  { size = 9,  style = 'LightGrid-Accent1-Tight', pad = 0.062 },
  { size = 8,  style = 'LightGrid-Accent1-Tight', pad = 0.062 },
  { size = 7,  style = 'LightGrid-Accent1-Tight', pad = 0.062 },
  { size = 6,  style = 'LightGrid-Accent1-Tight', pad = 0.062 },
}

local stringify = pandoc.utils.stringify

local function custom_style(name)
  return pandoc.Attr('', {}, { ['custom-style'] = name })
end

-- width of a text in em (Cambria, the body font of the guide)
local function text_em(s)
  local em = 0
  for _, code in utf8.codes(s) do
    local ch = utf8.char(code)
    if ch:match('%d') then
      em = em + 0.555
    elseif ch:match('[%s.,;:\'!|]') or ch == nbsp then
      em = em + 0.22
    elseif ch:match('[ijlrtf()%[%]%-/]') then
      em = em + 0.38
    elseif ch:match('[%u%%mw&@]') then
      em = em + 0.72
    else
      em = em + 0.54
    end
  end
  return em * safety
end

local function longest_word_em(s)
  local longest = 0
  for word in s:gmatch('%S+') do
    longest = math.max(longest, text_em(word))
  end
  return longest
end

local function is_text_column(tbl, i)
  local align = tbl.colspecs[i][1]
  return align == 'AlignLeft' or align == 'AlignDefault'
end

-- em each column needs: header cells may wrap between words, body cells
-- stay on one line, except text longer than max_text_chars
local function measure(tbl)
  local ncol = #tbl.colspecs
  local need, wraps = {}, {}
  for i = 1, ncol do
    need[i] = 0.5
    wraps[i] = false
  end
  local function scan(rows, is_head)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        if i <= ncol then
          local s = stringify(cell.contents)
          local em
          if is_head then
            em = longest_word_em(s)
          elseif is_text_column(tbl, i)
              and (utf8.len(s) or #s) > max_text_chars then
            wraps[i] = true
            em = math.max(longest_word_em(s), 0.54 * max_text_chars)
          else
            em = text_em(s)
          end
          need[i] = math.max(need[i], em)
        end
      end
    end
  end
  scan(tbl.head.rows, true)
  for _, body in ipairs(tbl.bodies) do
    scan(body.head, true)
    scan(body.body, false)
  end
  scan(tbl.foot.rows, false)
  local total = 0
  for _, em in ipairs(need) do total = total + em end
  return total, wraps
end

-- first layout that fits the page; the smallest one if none fits
local function choose_tier(tbl, total_em, forced_size)
  local ncol = #tbl.colspecs
  local chosen, fits = nil, false
  for _, tier in ipairs(tiers) do
    if not forced_size or tier.size == forced_size then
      chosen = tier
      fits = total_em * tier.size / 72 + ncol * tier.pad <= text_width
      if fits then break end
    end
  end
  chosen = chosen or tiers[#tiers]
  if not fits then
    io.stderr:write('guide_tables.lua: a table with ', ncol,
                    ' columns does not fit the page at ', chosen.size,
                    ' pt (', stringify(tbl.caption.long), ')\n')
  end
  return chosen
end

-- cell paragraphs: Plain keeps pandoc's "Compact" (10 pt); smaller sizes
-- need a Para inside a Div with the paragraph style "Table Text <size>"
local function style_cell(cell, size, bold, no_wrap)
  local blocks = {}
  for _, block in ipairs(cell.contents) do
    if block.t == 'Plain' or block.t == 'Para' then
      local inlines = block.content
      if no_wrap then
        inlines = inlines:walk({
          Space = function() return pandoc.Str(nbsp) end,
          SoftBreak = function() return pandoc.Str(nbsp) end,
        })
      end
      if bold and #inlines > 0 then
        inlines = { pandoc.Span(inlines, custom_style('Table First Column')) }
      end
      if size == 10 then
        block = pandoc.Plain(inlines)
      else
        block = pandoc.Para(inlines)
      end
    end
    blocks[#blocks + 1] = block
  end
  if size == 10 then
    cell.contents = blocks
  else
    cell.contents = { pandoc.Div(blocks, custom_style('Table Text ' .. size)) }
  end
end

local function style_rows(rows, size, is_body, wraps)
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row.cells) do
      style_cell(cell, size, is_body and first_column_bold and i == 1,
                 is_body and not wraps[i])
    end
  end
end

local spacer = pandoc.RawBlock(
  'openxml', '<w:p><w:pPr><w:pStyle w:val="TableSpacer"/></w:pPr></w:p>')

local function style_table(tbl)
  local forced_size = tonumber(tbl.attributes['table-font-size'])
  tbl.attributes['table-font-size'] = nil
  if forced_size and (forced_size < 6 or forced_size > 10) then
    forced_size = nil                 -- only 6 to 10 pt styles exist
  end
  local total_em, wraps = measure(tbl)
  local tier = choose_tier(tbl, total_em, forced_size)
  tbl.attributes['custom-style'] = tier.style
  -- no column widths: Word fits the columns to their contents
  for i, colspec in ipairs(tbl.colspecs) do
    tbl.colspecs[i] = { colspec[1], nil }
  end
  style_rows(tbl.head.rows, tier.size, false, wraps)
  for _, body in ipairs(tbl.bodies) do
    style_rows(body.head, tier.size, false, wraps)
    style_rows(body.body, tier.size, true, wraps)
  end
  style_rows(tbl.foot.rows, tier.size, true, wraps)
  return { tbl, spacer }
end

-- settings from the YAML header
local function read_meta(meta)
  local settings = meta['guide-tables']
  if type(settings) == 'table' then
    if settings['text-width'] then
      text_width = tonumber(stringify(settings['text-width'])) or text_width
    end
    if settings['first-column-bold'] ~= nil then
      first_column_bold = settings['first-column-bold'] == true
    end
  end
end

-- a Div with table-font-size passes the size on to its tables
local function mark_tables(div)
  local size = div.attributes['table-font-size']
  if size then
    return div:walk({
      Table = function(tbl)
        tbl.attributes['table-font-size'] = size
        return tbl
      end
    })
  end
end

-- tight lists: "List Paragraph" (11 pt) instead of pandoc's "Compact"
local function style_list(list)
  for i, item in ipairs(list.content) do
    local blocks = {}
    for _, block in ipairs(item) do
      if block.t == 'Plain' then
        block = pandoc.Div({ pandoc.Para(block.content) },
                           custom_style('List Paragraph'))
      end
      blocks[#blocks + 1] = block
    end
    list.content[i] = blocks
  end
  return list
end

if FORMAT:match('docx') then
  return {
    { Meta = read_meta },
    { Div = mark_tables },
    { BulletList = style_list, OrderedList = style_list },
    { Table = style_table },
  }
end
return {}
