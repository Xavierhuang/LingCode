# Building with LingCode: A Practical Guide

This guide shows you how to effectively use LingCode to build websites and applications, with real prompts and workflows.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Project Setup Prompts](#2-project-setup-prompts)
3. [Building a Website Step-by-Step](#3-building-a-website-step-by-step)
4. [Effective Prompting Strategies](#4-effective-prompting-strategies)
5. [Using LingCode Features](#5-using-lingcode-features)
6. [Common Workflows](#6-common-workflows)
7. [Tips and Best Practices](#7-tips-and-best-practices)

---

## 1. Getting Started

### Initial Setup

1. **Open your project folder** in LingCode
2. **Set your API key** (Settings > API Configuration)
3. **Create a WORKSPACE.md** file with project rules (optional but recommended)

### Example WORKSPACE.md

```markdown
# Project: My Portfolio Website

## Tech Stack
- Next.js 14 with App Router
- TypeScript
- Tailwind CSS
- Framer Motion for animations

## Coding Standards
- Use functional components with hooks
- Prefer server components when possible
- Use Tailwind for styling, no inline styles
- All components should be in /components folder
- Pages go in /app folder

## Design
- Modern, minimal aesthetic
- Dark mode support
- Mobile-first responsive design
```

---

## 2. Project Setup Prompts

### For a React/Next.js Website

```
Create a new Next.js 14 project with:
- TypeScript
- Tailwind CSS
- App Router
- ESLint configured

Set up the folder structure:
/app - pages and layouts
/components - reusable UI components
/lib - utilities and helpers
/public - static assets

Create the initial layout with a header, main content area, and footer.
```

### For a Simple HTML/CSS Website

```
Create a simple portfolio website with:
- index.html - home page
- about.html - about page
- contact.html - contact form
- styles.css - shared styles
- script.js - interactions

Use modern CSS (flexbox/grid), semantic HTML, and vanilla JavaScript.
Make it responsive for mobile.
```

### For a Full-Stack App

```
Set up a full-stack web app with:
- Frontend: React + Vite + TypeScript
- Backend: Node.js + Express
- Database: PostgreSQL with Prisma ORM
- Authentication: JWT

Create the folder structure and initial configuration files.
```

---

## 3. Building a Website Step-by-Step

### Phase 1: Structure and Layout

**Prompt 1 - Create the layout:**
```
Create a responsive layout component with:
- Header with logo and navigation (Home, About, Services, Contact)
- Main content area
- Footer with social links and copyright

Use Tailwind CSS. Make the header sticky. Add mobile hamburger menu.
```

**Prompt 2 - Create the navigation:**
```
Add a mobile-responsive navigation menu:
- Hamburger icon on mobile
- Slide-out menu with smooth animation
- Close when clicking outside or on a link
- Highlight active page
```

### Phase 2: Home Page

**Prompt 3 - Hero section:**
```
Create a hero section for the home page with:
- Large headline: "Building Digital Experiences"
- Subheadline with description
- CTA button "Get Started"
- Background gradient or subtle pattern
- Fade-in animation on load
```

**Prompt 4 - Features section:**
```
Add a features section with 3 cards:
1. Fast Performance - lightning icon
2. Modern Design - palette icon  
3. SEO Optimized - search icon

Each card should have icon, title, and description.
Use a grid layout, hover effects on cards.
```

**Prompt 5 - Testimonials:**
```
Create a testimonials carousel showing customer reviews:
- Profile image, name, role, company
- Quote text
- Star rating
- Auto-rotate every 5 seconds
- Manual navigation dots
```

### Phase 3: Inner Pages

**Prompt 6 - About page:**
```
Create an About page with:
- Team section with photo grid
- Company story/timeline
- Mission and values
- Stats counter (projects completed, clients, years)
```

**Prompt 7 - Services page:**
```
Create a Services page with:
- Service cards with icons
- Pricing table (3 tiers: Basic, Pro, Enterprise)
- FAQ accordion section
- CTA to contact
```

**Prompt 8 - Contact page:**
```
Create a Contact page with:
- Contact form (name, email, message)
- Form validation
- Success/error messages
- Contact info sidebar (email, phone, address)
- Embedded Google Map
```

### Phase 4: Polish and Features

**Prompt 9 - Dark mode:**
```
Add dark mode support:
- Toggle button in header
- Persist preference in localStorage
- Smooth transition between modes
- Update all colors for dark theme
```

**Prompt 10 - Animations:**
```
Add scroll animations using Framer Motion:
- Fade up for sections as they enter viewport
- Stagger animation for lists/grids
- Smooth page transitions
- Hover effects on buttons and links
```

**Prompt 11 - SEO and meta:**
```
Add SEO optimization:
- Meta tags for each page (title, description)
- Open Graph tags for social sharing
- Structured data (JSON-LD) for organization
- Sitemap.xml
- robots.txt
```

---

## 4. Effective Prompting Strategies

### Be Specific About Requirements

**Bad prompt:**
```
Make a nice header
```

**Good prompt:**
```
Create a header component with:
- Logo on the left (use text "BRAND" for now)
- Navigation links: Home, About, Services, Contact
- CTA button "Get Started" on the right
- Sticky positioning on scroll
- White background with subtle shadow when scrolled
- Mobile: hamburger menu that opens a full-screen overlay
```

### Provide Context

**Bad prompt:**
```
Add authentication
```

**Good prompt:**
```
Add user authentication to my Next.js app:
- Use NextAuth.js with credentials provider
- Login page at /login
- Register page at /register  
- Protect /dashboard routes
- Store user session
- Add login/logout buttons to header
- Redirect to /dashboard after login
```

### Use @mentions for Context

```
@src/components/Header.tsx - Update the header to include a user dropdown 
when logged in, showing their avatar and a logout button.
```

```
@src/styles/globals.css - Add CSS variables for the color palette:
primary: blue-600, secondary: gray-600, accent: purple-500
```

### Break Down Large Tasks

Instead of:
```
Build me a complete e-commerce website
```

Do this:
```
Step 1: Create the product listing page with a grid of product cards

Step 2: Create the product detail page with image gallery, description, 
and add-to-cart button

Step 3: Create the shopping cart with quantity controls and price calculation

Step 4: Create the checkout flow with shipping and payment forms
```

---

## 5. Using LingCode Features

### Slash Commands

Use these quick commands:

| Command | Use Case |
|---------|----------|
| `/commit` | Create a git commit with AI-generated message |
| `/review` | Review your current file for issues |
| `/test` | Generate tests for your code |
| `/doc` | Add documentation comments |
| `/fix` | Fix linting or compilation errors |
| `/refactor` | Suggest code improvements |
| `/explain` | Understand complex code |

### @Mentions

Reference context in your prompts:

| Mention | What It Does |
|---------|--------------|
| `@file.tsx` | Include specific file content |
| `@src/components/` | Include folder contents |
| `@codebase` | Search entire codebase |
| `@web` | Search the web for current info |
| `@docs` | Search documentation |
| `@terminal` | Include terminal output |

### Agent Mode

For complex multi-step tasks, use Agent Mode:

```
Agent: Build a complete blog system with:
1. Post listing page with pagination
2. Individual post page with markdown rendering
3. Admin page to create/edit posts
4. Categories and tags
5. Search functionality

Use the existing database schema in @prisma/schema.prisma
```

The agent will:
- Plan the approach
- Create files one by one
- Run necessary commands
- Validate the code
- Apply changes when ready

### Composer (Multi-file Generation)

For generating multiple related files at once:

```
Generate a complete user authentication system:
- /components/LoginForm.tsx
- /components/RegisterForm.tsx
- /lib/auth.ts
- /app/api/auth/route.ts
- /middleware.ts for route protection
```

---

## 6. Common Workflows

### Workflow 1: Adding a New Feature

1. **Describe the feature:**
   ```
   Add a newsletter signup form to the footer with email validation
   and integration with Mailchimp API
   ```

2. **Review the generated code** in the diff view

3. **Ask for adjustments:**
   ```
   Make the form inline (email input + button on same row) and add 
   a success toast notification
   ```

4. **Apply changes** when satisfied

5. **Test and commit:**
   ```
   /commit
   ```

### Workflow 2: Fixing a Bug

1. **Describe the issue:**
   ```
   The mobile menu doesn't close when clicking a link. 
   @components/MobileMenu.tsx
   ```

2. **Or use the fix command:**
   ```
   /fix - The navigation links don't work on mobile
   ```

3. **Review and apply** the fix

### Workflow 3: Refactoring

1. **Ask for analysis:**
   ```
   /review @components/ProductCard.tsx - suggest improvements
   ```

2. **Request specific refactoring:**
   ```
   /refactor - Extract the price formatting logic into a separate 
   utility function and add proper TypeScript types
   ```

### Workflow 4: Adding Tests

1. **Generate tests:**
   ```
   /test @components/LoginForm.tsx
   ```

2. **Or be specific:**
   ```
   Write unit tests for the LoginForm component covering:
   - Empty form submission
   - Invalid email format
   - Successful submission
   - API error handling
   ```

---

## 7. Tips and Best Practices

### Do's

1. **Start with structure** - Create folder structure and base components first
2. **Work incrementally** - Build one feature at a time
3. **Use @mentions** - Give context for better results
4. **Review before applying** - Check the diff view
5. **Commit often** - Use `/commit` after each feature
6. **Be specific** - Include details about styling, behavior, edge cases
7. **Iterate** - Ask for adjustments rather than starting over

### Don'ts

1. **Don't ask for everything at once** - Break into smaller tasks
2. **Don't skip the review** - Always check generated code
3. **Don't ignore errors** - Use `/fix` to resolve issues
4. **Don't forget mobile** - Always mention responsive requirements
5. **Don't be vague** - "Make it better" doesn't help

### Prompt Templates

**For new components:**
```
Create a [ComponentName] component that:
- [Functionality 1]
- [Functionality 2]
- Props: [list props with types]
- Styling: [Tailwind/CSS approach]
- State: [what state it manages]
- Events: [what events it handles]
```

**For API routes:**
```
Create an API route at [path] that:
- Method: [GET/POST/PUT/DELETE]
- Input: [request body/params]
- Output: [response format]
- Validation: [what to validate]
- Error handling: [how to handle errors]
- Database: [what queries to run]
```

**For pages:**
```
Create a [page name] page with:
- Layout: [describe layout]
- Sections: [list sections]
- Data: [what data it needs]
- SEO: [title, description]
- Mobile: [responsive behavior]
```

---

## Example: Building a Landing Page from Scratch

Here's a complete workflow for building a SaaS landing page:

### Step 1: Project Setup
```
Create a Next.js 14 landing page project with TypeScript and Tailwind.
Set up a clean folder structure. Create placeholder pages for 
Home, Features, Pricing, and Contact.
```

### Step 2: Layout
```
Create a Layout component with:
- Header: Logo, nav links (Features, Pricing), CTA button "Start Free Trial"
- Footer: Company info, links, social icons, newsletter signup
- Smooth scroll behavior for anchor links
```

### Step 3: Hero Section
```
Create a Hero section with:
- Headline: "Ship Faster with AI-Powered Development"
- Subheadline explaining the product value
- Email input + "Get Early Access" button
- Hero image or illustration on the right
- Gradient background
- Trusted by logos row
```

### Step 4: Features
```
Create a Features section with:
- Section headline "Everything you need to build faster"
- 6 feature cards in 3x2 grid
- Each card: icon, title, description
- Alternating icon colors
- Hover animation (slight lift + shadow)
```

### Step 5: How It Works
```
Create a "How It Works" section with 3 steps:
1. Connect your repo
2. Describe what you want
3. Review and ship

Show as horizontal timeline on desktop, vertical on mobile.
Include simple illustrations for each step.
```

### Step 6: Pricing
```
Create a Pricing section with 3 tiers:
- Free: $0, basic features, individual use
- Pro: $29/mo, advanced features, team use
- Enterprise: Custom, all features, dedicated support

Highlight Pro as "Most Popular"
Include feature comparison list
Add toggle for monthly/annual (20% discount)
```

### Step 7: Testimonials
```
Create a Testimonials section with:
- Carousel of 5 testimonials
- Each: photo, name, role, company logo, quote
- Auto-rotate every 5 seconds
- Dots navigation
- Pause on hover
```

### Step 8: CTA Section
```
Create a final CTA section with:
- Dark background
- "Ready to ship faster?"
- Secondary text
- Two buttons: "Start Free Trial" and "Book a Demo"
```

### Step 9: Polish
```
Add animations throughout:
- Fade up on scroll for all sections
- Stagger animation for feature cards
- Smooth hover transitions
- Page load animation for hero

Add dark mode toggle in header.
Ensure all sections are mobile responsive.
```

### Step 10: SEO & Deploy
```
Add SEO:
- Page title and meta description
- Open Graph image
- Favicon
- Sitemap

Set up deployment to Vercel.
```

---

## Quick Reference Card

### Starting a Prompt
- "Create a..." - For new components/features
- "Add..." - For adding to existing code
- "Update..." - For modifying existing code
- "Fix..." - For bug fixes
- "Refactor..." - For code improvements

### Ending a Prompt
- "Use TypeScript" - For type safety
- "Use Tailwind CSS" - For styling
- "Make it responsive" - For mobile support
- "Add error handling" - For robustness
- "Include loading states" - For UX

### Magic Phrases
- "Follow the existing code style" - Maintains consistency
- "Based on @filename" - Uses existing code as reference
- "Similar to how X does it" - Follows patterns
- "With proper TypeScript types" - Ensures type safety
- "Production-ready" - Includes error handling, edge cases

---

*Happy building with LingCode!*
