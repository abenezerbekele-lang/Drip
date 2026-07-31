import fs from "node:fs/promises";
import {
  Presentation,
  PresentationFile,
} from "@oai/artifact-tool";

const ROOT = "/Users/abeniizerbekele/drip";
const OUT = `${ROOT}/deliverables/drip_pitch_deck.pptx`;
const PREVIEW_DIR = `${ROOT}/.deck_work/rendered`;

const W = 1280;
const H = 720;
const INK = "#080B10";
const NAVY = "#0D1727";
const PAPER = "#F4F6F2";
const WHITE = "#FFFFFF";
const BLUE = "#63ADFF";
const ICE = "#A8D5FF";
const MUTED = "#A8B0BC";
const DARK_MUTED = "#667080";
const LINE = "#293445";

const presentation = Presentation.create({
  slideSize: { width: W, height: H },
});

async function imageBytes(path) {
  const bytes = await fs.readFile(path);
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  );
}

function textBox(
  slide,
  text,
  position,
  {
    size = 24,
    color = INK,
    bold = false,
    fill = "none",
    name,
    line = "none",
  } = {},
) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    name,
    position,
    fill,
    line: { style: "solid", fill: line, width: 0 },
  });
  shape.text = text;
  shape.text.style = {
    fontSize: size,
    color,
    bold,
  };
  return shape;
}

function rect(
  slide,
  position,
  {
    fill = INK,
    line = "none",
    width = 0,
    radius = 0,
    name,
    shadow,
  } = {},
) {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    name,
    position,
    fill,
    line: { style: "solid", fill: line, width },
    ...(radius ? { borderRadius: radius } : {}),
    ...(shadow ? { shadow } : {}),
  });
}

function rule(slide, left, top, width, color = BLUE, weight = 3) {
  slide.shapes.add({
    geometry: "line",
    position: { left, top, width, height: 0 },
    fill: "none",
    line: { style: "solid", fill: color, width: weight },
  });
}

function eyebrow(slide, text, left, top, color = DARK_MUTED) {
  rule(slide, left, top + 10, 34, BLUE, 3);
  return textBox(
    slide,
    text.toUpperCase(),
    { left: left + 48, top, width: 440, height: 30 },
    { size: 14, color, bold: true },
  );
}

async function picture(slide, path, position, alt, options = {}) {
  return slide.images.add({
    blob: await imageBytes(path),
    contentType: path.endsWith(".png") ? "image/png" : "image/jpeg",
    alt,
    fit: options.fit ?? "cover",
    position,
    ...(options.radius
      ? { geometry: "roundRect", borderRadius: options.radius }
      : {}),
    ...(options.crop ? { crop: options.crop } : {}),
  });
}

function footer(slide, number, label) {
  textBox(
    slide,
    `0${number}`,
    { left: 70, top: 676, width: 42, height: 22 },
    { size: 13, color: BLUE, bold: true },
  );
  textBox(
    slide,
    label.toUpperCase(),
    { left: 106, top: 676, width: 300, height: 22 },
    { size: 13, color: DARK_MUTED, bold: true },
  );
}

function notes(slide, sourceLines, talkTrack) {
  slide.speakerNotes.textFrame.setText(
    `${talkTrack}\n\n[Sources]\n${sourceLines
      .map((line) => `- ${line}`)
      .join("\n")}`,
  );
  slide.speakerNotes.setVisible(true);
}

// Slide 1 — minimal opening
{
  const slide = presentation.slides.add();
  slide.background.fill = INK;
  await picture(
    slide,
    `${ROOT}/deliverables/website-hero.png`,
    { left: 0, top: 0, width: W, height: H },
    "Drip production website hero with two people shopping at a night market",
  );
  rect(
    slide,
    { left: 54, top: 42, width: 208, height: 38 },
    { fill: BLUE, radius: 12 },
  );
  textBox(
    slide,
    "DRIP / PRODUCT PITCH",
    { left: 70, top: 51, width: 180, height: 22 },
    { size: 13, color: INK, bold: true },
  );
  rect(
    slide,
    { left: 814, top: 626, width: 408, height: 50 },
    { fill: INK, radius: 16 },
  );
  textBox(
    slide,
    "AI-GUIDED FASHION MARKETPLACE",
    { left: 841, top: 643, width: 354, height: 22 },
    { size: 15, color: WHITE, bold: true },
  );
  notes(
    slide,
    [
      "Internal Drip website capture: deliverables/website-hero.png",
      "Internal Drip editorial asset: assets/editorial/drip_night_market_editorial_v3.jpg",
    ],
    "Open on the customer promise: Drip helps people move from inspiration to a complete fit and a protected purchase.",
  );
}

// Slide 2 — problem and differentiated value
{
  const slide = presentation.slides.add();
  slide.background.fill = PAPER;
  eyebrow(slide, "The customer gap", 70, 62);
  textBox(
    slide,
    "Products are easy.\nDecisions are personal.",
    { left: 70, top: 120, width: 530, height: 180 },
    { size: 49, color: INK, bold: true },
  );
  textBox(
    slide,
    "Resale discovery is visual, but the decision is personal: budget, fit, occasion, confidence, trust, and payment all happen in the same moment.",
    { left: 70, top: 330, width: 500, height: 90 },
    { size: 18, color: DARK_MUTED },
  );

  const valueY = [452, 512, 572];
  const valueCopy = [
    ["DISCOVER", "Editorial context, not a generic feed"],
    ["ASK", "Professional answers to flexible style questions"],
    ["BUY", "Server-verified totals and Stripe-hosted payment"],
  ];
  valueCopy.forEach(([label, copy], index) => {
    textBox(
      slide,
      label,
      { left: 70, top: valueY[index], width: 108, height: 24 },
      { size: 14, color: BLUE, bold: true },
    );
    textBox(
      slide,
      copy,
      { left: 188, top: valueY[index] - 3, width: 390, height: 48 },
      { size: 19, color: INK, bold: true },
    );
  });

  await picture(
    slide,
    `${ROOT}/deliverables/website-experience.png`,
    { left: 646, top: 110, width: 566, height: 318 },
    "Drip discovery website showing editorial fashion content and product presentation",
    { radius: 24, fit: "contain" },
  );
  rect(
    slide,
    { left: 646, top: 454, width: 566, height: 160 },
    { fill: INK, radius: 24 },
  );
  textBox(
    slide,
    "Context earns attention.\nAdvice earns confidence.",
    { left: 684, top: 486, width: 490, height: 88 },
    { size: 30, color: WHITE, bold: true },
  );
  footer(slide, 2, "Customer value");
  notes(
    slide,
    [
      "Internal Drip product experience capture: deliverables/website-experience.png",
      "Internal product requirements and UX: README.md",
    ],
    "Frame the gap as decision support. Drip connects discovery, advice, and commerce instead of treating them as separate tools.",
  );
}

// Slide 3 — end-to-end product flow
{
  const slide = presentation.slides.add();
  slide.background.fill = INK;
  eyebrow(slide, "One connected experience", 70, 52, MUTED);
  textBox(
    slide,
    "Inspiration becomes confidence—then checkout.",
    { left: 70, top: 94, width: 1140, height: 58 },
    { size: 44, color: WHITE, bold: true },
  );

  const frames = [
    {
      path: `${ROOT}/deliverables/video_frames/frame-5.png`,
      x: 70,
      label: "01 / DISCOVER",
      copy: "Editorial + trust signals",
    },
    {
      path: `${ROOT}/deliverables/video_frames/frame-25.png`,
      x: 455,
      label: "02 / STYLE",
      copy: "Budget-aware outfit guidance",
    },
    {
      path: `${ROOT}/deliverables/video_frames/frame-105.png`,
      x: 840,
      label: "03 / CHECKOUT",
      copy: "Verified Stripe totals",
    },
  ];
  for (const frame of frames) {
    rect(
      slide,
      { left: frame.x, top: 176, width: 340, height: 494 },
      { fill: NAVY, radius: 26, line: LINE, width: 1, shadow: "shadow-lg" },
    );
    textBox(
      slide,
      frame.label,
      { left: frame.x + 24, top: 201, width: 274, height: 24 },
      { size: 13, color: BLUE, bold: true },
    );
    textBox(
      slide,
      frame.copy,
      { left: frame.x + 24, top: 230, width: 292, height: 48 },
      { size: 18, color: WHITE, bold: true },
    );
    rect(
      slide,
      { left: frame.x + 71, top: 270, width: 198, height: 386 },
      { fill: INK, radius: 21, line: LINE, width: 1 },
    );
    await picture(
      slide,
      frame.path,
      { left: frame.x + 80, top: 280, width: 180, height: 392 },
      `${frame.label} mobile app screen`,
      { radius: 16 },
    );
  }
  notes(
    slide,
    [
      "Internal two-minute walkthrough frames: deliverables/video_frames/frame-5.png, frame-25.png, frame-105.png",
      "Internal AI and checkout behavior: docs/TECHNICAL_DOCUMENTATION.md",
    ],
    "Walk left to right. The value is the continuity: discovery context informs the stylist, and the selected product moves into a transparent checkout.",
  );
}

// Slide 4 — production architecture and trust
{
  const slide = presentation.slides.add();
  slide.background.fill = PAPER;
  eyebrow(slide, "Trust is the architecture", 70, 56);
  textBox(
    slide,
    "Private data stays private.\nPayment authority stays off the client.",
    { left: 70, top: 104, width: 1100, height: 104 },
    { size: 43, color: INK, bold: true },
  );

  await picture(
    slide,
    `${ROOT}/deliverables/website-launch.png`,
    { left: 70, top: 228, width: 738, height: 386 },
    "Drip architecture from Flutter through Node, Firestore and SQL, to Stripe",
    { radius: 26, crop: { left: 0.04, top: 0.05, right: 0.04, bottom: 0.04 } },
  );

  const trustItems = [
    ["EMAIL VERIFIED", "Confirmation codes before account activation"],
    ["SPLIT DATA AUTHORITY", "Firestore catalog; SQL for transactional truth"],
    ["STRIPE HOSTED", "No raw card details enter Drip"],
    ["WEBHOOK CONFIRMED", "Redirects never declare an order paid"],
  ];
  trustItems.forEach(([title, copy], index) => {
    const y = 232 + index * 92;
    textBox(
      slide,
      `0${index + 1}`,
      { left: 850, top: y + 2, width: 34, height: 23 },
      { size: 13, color: BLUE, bold: true },
    );
    textBox(
      slide,
      title,
      { left: 894, top: y, width: 290, height: 26 },
      { size: 17, color: INK, bold: true },
    );
    textBox(
      slide,
      copy,
      { left: 894, top: y + 31, width: 290, height: 52 },
      { size: 17, color: DARK_MUTED },
    );
  });
  footer(slide, 4, "Trust & architecture");
  notes(
    slide,
    [
      "Internal architecture capture: deliverables/website-launch.png",
      "Internal technical documentation: docs/TECHNICAL_DOCUMENTATION.md",
      "Internal backend setup and security boundaries: server/README.md",
    ],
    "Emphasize the split authority. Firestore serves marketplace catalog documents, while SQL preserves atomic identity, inventory, order, and payment invariants.",
  );
}

// Slide 5 — business model
{
  const slide = presentation.slides.add();
  slide.background.fill = INK;
  await picture(
    slide,
    `${ROOT}/assets/products/rack_baggy_denim_natural_v2.jpg`,
    { left: 640, top: 0, width: 640, height: H },
    "Baggy denim photographed in natural window light",
  );
  rect(
    slide,
    { left: 0, top: 0, width: 654, height: H },
    { fill: INK },
  );
  eyebrow(slide, "Business model", 70, 56, MUTED);
  textBox(
    slide,
    "Four revenue paths grow with marketplace activity.",
    { left: 70, top: 106, width: 500, height: 214 },
    { size: 49, color: WHITE, bold: true },
  );
  textBox(
    slide,
    "4",
    { left: 70, top: 326, width: 110, height: 92 },
    { size: 78, color: ICE, bold: true },
  );
  textBox(
    slide,
    "MONETIZATION LAYERS",
    { left: 170, top: 352, width: 250, height: 30 },
    { size: 15, color: MUTED, bold: true },
  );

  const revenues = [
    "Transaction fee",
    "Buyer protection",
    "Listing boosts",
    "Drip Pro subscription",
  ];
  revenues.forEach((label, index) => {
    const x = index % 2 === 0 ? 70 : 296;
    const y = index < 2 ? 452 : 530;
    rule(slide, x, y, 182, index === 3 ? ICE : BLUE, 2);
    textBox(
      slide,
      label,
      { left: x, top: y + 14, width: 205, height: 46 },
      { size: 19, color: WHITE, bold: true },
    );
  });
  textBox(
    slide,
    "No invented traction figures. The model is designed and instrumented; launch validation comes next.",
    { left: 70, top: 618, width: 500, height: 52 },
    { size: 16, color: MUTED },
  );
  notes(
    slide,
    [
      "Internal seller experience capture: deliverables/website-seller.png",
      "Internal business model: docs/BUSINESS_MODEL.md",
      "Internal commerce policy implementation: lib/commerce_model.dart",
    ],
    "Keep the claim disciplined: the product contains four monetization mechanisms, but no market traction or revenue is claimed before a real pilot.",
  );
}

// Slide 6 — production launch ask
{
  const slide = presentation.slides.add();
  slide.background.fill = PAPER;
  eyebrow(slide, "The launch path", 70, 56);
  textBox(
    slide,
    "The product is built.\nProduction credentials unlock the market.",
    { left: 70, top: 104, width: 820, height: 166 },
    { size: 48, color: INK, bold: true },
  );
  textBox(
    slide,
    "Seeking a launch partner and a focused beta community of sellers and style-conscious shoppers.",
    { left: 70, top: 294, width: 760, height: 62 },
    { size: 21, color: DARK_MUTED },
  );

  const steps = [
    {
      number: "01",
      title: "CONNECT",
      copy: "Owner Firebase, Stripe, Resend, and OpenAI production credentials",
    },
    {
      number: "02",
      title: "DEPLOY",
      copy: "Backend API, webhooks, real inventory, monitoring, and support",
    },
    {
      number: "03",
      title: "PILOT",
      copy: "Invite sellers, observe conversion, and validate the revenue model",
    },
  ];
  steps.forEach((step, index) => {
    const x = 70 + index * 385;
    rect(
      slide,
      { left: x, top: 390, width: 340, height: 190 },
      {
        fill: index === 0 ? INK : WHITE,
        radius: 24,
        line: index === 0 ? INK : "#D6DCE4",
        width: 1,
        shadow: "shadow-sm",
      },
    );
    textBox(
      slide,
      step.number,
      { left: x + 22, top: 412, width: 42, height: 24 },
      { size: 14, color: BLUE, bold: true },
    );
    textBox(
      slide,
      step.title,
      { left: x + 22, top: 452, width: 190, height: 32 },
      { size: 25, color: index === 0 ? WHITE : INK, bold: true },
    );
    textBox(
      slide,
      step.copy,
      { left: x + 22, top: 498, width: 292, height: 62 },
      { size: 18, color: index === 0 ? MUTED : DARK_MUTED },
    );
  });

  rect(
    slide,
    { left: 70, top: 624, width: 1140, height: 58 },
    { fill: BLUE, radius: 18 },
  );
  textBox(
    slide,
    "TWO-MINUTE NARRATED PRODUCT WALKTHROUGH INCLUDED WITH THIS SUBMISSION",
    { left: 94, top: 642, width: 1090, height: 24 },
    { size: 17, color: INK, bold: true },
  );
  notes(
    slide,
    [
      "Internal production roadmap: docs/PRODUCTION_ROADMAP.md",
      "Internal requirement mapping: docs/REQUIREMENTS_CHECKLIST.md",
      "Internal narrated demo: deliverables/drip_demo_2min.mp4",
    ],
    "Close with the concrete next decision: provide the owner credentials, deploy the backend, and run a measured pilot with a narrow customer segment.",
  );
}

await fs.mkdir(PREVIEW_DIR, { recursive: true });
for (const [index, slide] of presentation.slides.items.entries()) {
  const stem = `slide-${String(index + 1).padStart(2, "0")}`;
  const png = await presentation.export({ slide, format: "png", scale: 1 });
  await fs.writeFile(
    `${PREVIEW_DIR}/${stem}.png`,
    new Uint8Array(await png.arrayBuffer()),
  );
  const layout = await slide.export({ format: "layout" });
  await fs.writeFile(
    `${PREVIEW_DIR}/${stem}.layout.json`,
    await layout.text(),
  );
}

const montage = await presentation.export({
  format: "webp",
  montage: true,
  scale: 1,
});
await fs.writeFile(
  `${PREVIEW_DIR}/deck-montage.webp`,
  new Uint8Array(await montage.arrayBuffer()),
);

const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(OUT);
console.log(OUT);
