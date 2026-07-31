require 'fileutils'

def run_with_progress(label, cmd)
  spinners = ['|', '/', '-', '\\']
  i = 0

  pid = Process.spawn("#{cmd} > /dev/null 2>&1")

  print "\x1b[1;36m[Compiling]\x1b[0m #{label} ... "

  while Process.waitpid(pid, Process::WNOHANG).nil?
    print "\r\x1b[1;36m[Building]\x1b[0m #{label} [#{spinners[i % spinners.length]}]"
    sleep 0.1
    i += 1
  end

  if $?.exitstatus != 0
    puts "\r\x1b[1;31m[Failed]\x1b[0m #{label}                     "
    raise "Command failed: #{cmd}"
  else
    puts "\r\x1b[1;32m[Finished]\x1b[0m #{label} [====================>] 100%"
  end
end

run_with_progress("Bolma (Init)", "cargo new --quiet Bolma")

Dir.chdir("Bolma") do
  cargo_toml_content = <<~'TOML'
    [package]
    name = "Bolma"
    version = "0.1.0"
    edition = "2024"

    [dependencies]
    pest = "2.7"
    pest_derive = "2.7"
  TOML

  File.write("Cargo.toml", cargo_toml_content)

  build_sh_content = <<~'SHELL'
    #!/bin/sh
    cargo build --quiet --release > /dev/null 2>&1 && cp target/release/bolma ./Bolma
  SHELL

  File.write("build.sh", build_sh_content)
  FileUtils.chmod(0755, "build.sh")

  bolma_wrapper_content = <<~'SHELL'
    #!/bin/sh
    if [ ! -f ./Bolma ]; then
      cargo build --quiet --release > /dev/null 2>&1 && cp target/release/bolma ./Bolma
    fi
    ./Bolma "$@"
  SHELL

  File.write("bolma", bolma_wrapper_content)
  FileUtils.chmod(0755, "bolma")

  main_rs_content = <<~'RUST'
    mod bolma;

    use std::env;

    fn main() {
        let args: Vec<String> = env::args().collect();

        if args.len() < 2 {
            println!("\x1b[1;33mERROR\x1b[0m Missing command or target file.");
            println!("\nUsage:");
            println!("  bolma run <file.bolma>");
            println!("  bolma <file.bolma>");
            return;
        }

        let command = &args[1];

        match command.as_str() {
            "--help" | "-h" => {
                println!("Bolma CLI Tool");
                println!("Usage:");
                println!("  bolma run <file.bolma>   Compiles and runs a layout");
                println!("  bolma <file.bolma>       Direct shorthand to run layout");
            }
            "run" => {
                if args.len() < 3 {
                    println!("\x1b[1;33mERROR\x1b[0m Please specify a file to run.");
                    return;
                }
                let filepath = &args[2];
                if let Err(e) = bolma::compile_and_run(filepath) {
                    eprintln!("\x1b[1;31mERROR\x1b[0m {}", e);
                }
            }
            filepath => {
                if let Err(e) = bolma::compile_and_run(filepath) {
                    eprintln!("\x1b[1;31mERROR\x1b[0m {}", e);
                }
            }
        }
    }
  RUST

  File.write("src/main.rs", main_rs_content)

  bolma_rs_content = <<~'RUST'
    use pest::Parser;
    use pest_derive::Parser;
    use std::collections::HashMap;
    use std::fs;
    use std::path::Path;
    use std::process::Command;

    #[derive(Parser)]
    #[grammar = "bolma.pest"]
    pub struct BolmaParser;

    #[derive(Debug, Default)]
    struct Element {
        name: String,
        props: HashMap<String, String>,
        children: Vec<Element>,
    }

    impl Element {
        fn to_html(&self) -> String {
            let norm = self.name.to_lowercase();
            let mut style = String::new();

            if let Some(pos) = self.props.get("position") {
                let parts: Vec<&str> = pos.split_whitespace().collect();
                if parts.len() >= 2 {
                    let left = parts[0].parse::<f64>().unwrap_or(0.0) * 100.0;
                    let top = parts[1].parse::<f64>().unwrap_or(0.0) * 100.0;
                    style.push_str(&format!("position: absolute; left: {}%; top: {}%; ", left, top));
                }
            }

            if let Some(size) = self.props.get("size") {
                let parts: Vec<&str> = size.split_whitespace().collect();
                if parts.len() >= 2 {
                    let w = parts[0].parse::<f64>().unwrap_or(0.0) * 100.0;
                    let h = parts[1].parse::<f64>().unwrap_or(0.0) * 100.0;
                    if norm == "text" {
                        style.push_str(&format!("font-size: {}px; ", w));
                    } else {
                        style.push_str(&format!("width: {}vw; height: {}vh; ", w, h));
                    }
                }
            }

            let bg_color = self
                .props
                .get("background")
                .or_else(|| self.props.get("bg"))
                .or_else(|| self.props.get("color"));

            if let Some(bg) = bg_color {
                let clean = bg.trim_matches('"');
                if norm == "text" {
                    style.push_str(&format!("color: {}; ", clean));
                } else {
                    style.push_str(&format!("background-color: {}; ", clean));
                }
            }

            if let Some(radius) = self.props.get("border-radius") {
                style.push_str(&format!("border-radius: {}px; ", radius));
            } else if norm == "circle" {
                style.push_str("border-radius: 50%; ");
            }

            let mut inner_html = String::new();
            for child in &self.children {
                inner_html.push_str(&child.to_html());
            }

            let text_content = self.props.get("text").map(|t| t.trim_matches('"')).unwrap_or("");

            match norm.as_str() {
                "vstack" => format!("<div style='display: flex; flex-direction: column; gap: 10px; {}'>{}</div>", style, inner_html),
                "hstack" => format!("<div style='display: flex; flex-direction: row; gap: 10px; {}'>{}</div>", style, inner_html),
                "zstack" => format!("<div style='position: relative; {}'>{}</div>", style, inner_html),
                "text" => format!("<span style='{}'>{}</span>", style, text_content),
                "button" => {
                    let action = self.props.get("action").or_else(|| self.props.get("onclick"))
                        .map(|a| format!("onclick=\"{}\"", a.trim_matches('"')))
                        .unwrap_or_else(|| "onclick=\"alert('Clicked!')\"".to_string());
                    let label = if text_content.is_empty() { "Button" } else { text_content };
                    format!("<button style='cursor: pointer; border: none; padding: 10px 20px; {}' {}>{}</button>", style, action, label)
                }
                "circle" | "rectangle" | "unevenroundedrectangle" => {
                    let text_span = if !text_content.is_empty() { format!("<span>{}</span>", text_content) } else { String::new() };
                    format!("<div style='display: flex; align-items: center; justify-content: center; min-width: 40px; min-height: 40px; {}'>{}{}" , style, text_span, inner_html)
                }
                _ => format!("<div style='{}'>{}</div>", style, inner_html),
            }
        }
    }

    fn parse_element(pair: pest::iterators::Pair<Rule>) -> Element {
        let mut elem = Element::default();
        for inner in pair.into_inner() {
            match inner.as_rule() {
                Rule::ident => elem.name = inner.as_str().to_string(),
                Rule::prop => {
                    let mut prop_inner = inner.into_inner();
                    let key = prop_inner.next().unwrap().as_str().to_string();
                    let val = prop_inner.next().unwrap().as_str().to_string();
                    elem.props.insert(key, val);
                }
                Rule::element => elem.children.push(parse_element(inner)),
                _ => {}
            }
        }
        elem
    }

    pub fn compile_and_run(filepath: &str) -> Result<(), String> {
        let unparsed_file = fs::read_to_string(filepath)
            .map_err(|_| format!("Could not read file target: {}", filepath))?;

        let start_time = std::time::Instant::now();

        let use_browser = unparsed_file.contains("import { BrowserWindow }")
            || unparsed_file.contains("import {BrowserWindow}");

        let file_pair = BolmaParser::parse(Rule::file, &unparsed_file)
            .map_err(|e| format!("Syntax error in {}:\n{}", filepath, e))?
            .next()
            .unwrap();

        let mut body_html = String::new();
        let mut page_bg = String::from("#ffffff");

        for pair in file_pair.into_inner() {
            match pair.as_rule() {
                Rule::prop => {
                    let mut inner = pair.into_inner();
                    let key = inner.next().unwrap().as_str();
                    let val = inner.next().unwrap().as_str();
                    if key == "background" || key == "bg" {
                        page_bg = val.trim_matches('"').to_string();
                    }
                }
                Rule::element => {
                    let elem = parse_element(pair);
                    body_html.push_str(&elem.to_html());
                }
                _ => {}
            }
        }

        let final_html = format!(
            "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Bolma Layout</title><style>body {{ font-family: Helvetica, sans-serif; background: {}; color: #111; margin: 40px; }}</style></head><body>{}</body></html>",
            page_bg, body_html
        );

        let html_path = Path::new("layout.html");
        fs::write(html_path, &final_html).map_err(|e| e.to_string())?;

        let abs_path = fs::canonicalize(html_path)
            .unwrap()
            .to_string_lossy()
            .into_owned();

        open_window(&abs_path, use_browser);
        Ok(())
    }

    fn open_window(html_path: &str, use_browser: bool) {
        let file_url = format!("file://{}", html_path);
        if use_browser {
            #[cfg(target_os = "macos")]
            let _ = Command::new("open").arg(&file_url).status();
            #[cfg(target_os = "windows")]
            let _ = Command::new("explorer").arg(&file_url).status();
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            let _ = Command::new("xdg-open").arg(&file_url).status();
        } else {
            #[cfg(target_os = "macos")]
            if Command::new("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
                .arg(format!("--app={}", file_url)).spawn().is_err() {
                let _ = Command::new("open").arg("-a").arg("Safari").arg(&file_url).status();
            }
            #[cfg(target_os = "windows")]
            if Command::new("msedge").arg(format!("--app={}", file_url)).spawn().is_err() {
                let _ = Command::new("explorer").arg(&file_url).status();
            }
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            if Command::new("google-chrome").arg(format!("--app={}", file_url)).spawn().is_err() {
                let _ = Command::new("xdg-open").arg(&file_url).status();
            }
        }
    }
  RUST

  File.write("src/bolma.rs", bolma_rs_content)

  bolma_pest_content = <<~'PEST'
    WHITESPACE = _{ " " | "\t" | "\r" | "\n" }
    COMMENT    = _{ "//" ~ (!"\n" ~ ANY)* }

    hex_color = @{ "#" ~ (ASCII_HEX_DIGIT{6} | ASCII_HEX_DIGIT{3}) }
    string    = @{ "\"" ~ (!"\"" ~ ANY)* ~ "\"" }
    number    = @{ ASCII_DIGIT+ ~ ("." ~ ASCII_DIGIT+)? }
    ident     = @{ (ASCII_ALPHA | "_" | "-") ~ (ASCII_ALPHANUMERIC | "_" | "-")* }

    value = { hex_color | string | number | ident }
    prop  = { ident ~ ":" ~ value }

    import_stmt = { "import" ~ "{" ~ ident ~ "}" ~ "from" ~ string }
    element     = { ident ~ "{" ~ (import_stmt | prop | element)* ~ "}" }

    file = { SOI ~ (import_stmt | prop | element)* ~ EOI }
  PEST

  File.write("src/bolma.pest", bolma_pest_content)

  layout_bolma_content = <<~'BOLMA'
    vstack {
        background: "#f0f0f0"
        text {
            text: "Welcome to Bolma!"
            color: "#333333"
            size: "24 24"
        }
        button {
            text: "Click Me"
            action: "alert('Hello from Bolma!')"
            background: "#007acc"
            color: "#ffffff"
        }
    }
  BOLMA

  File.write("layout.bolma", layout_bolma_content)

  run_with_progress("Bolma v0.1.0 release", "cargo build --release")
  FileUtils.cp("target/release/bolma", "./Bolma")
end

