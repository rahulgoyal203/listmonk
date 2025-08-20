# Subscription Form Integration Guide

This guide explains how to add subscriber signup forms to your website using Listmonk and set up automated welcome emails.

## Overview

Listmonk provides multiple ways to add subscribers to your mailing lists:

1. **Built-in Public Subscription Form** - Ready-to-use form hosted by Listmonk
2. **Custom Forms via Public API** - Create your own forms that integrate with Listmonk's public API
3. **Automated Email Triggers** - Send welcome/confirmation emails automatically

## Method 1: Built-in Public Subscription Form

Listmonk includes a ready-to-use subscription form template. Access it at:
```
http://your-listmonk-domain.com/subscription/form
```

**Features:**
- Pre-built HTML form with email and name fields
- List selection checkboxes
- CAPTCHA support (hCaptcha or ALTCHA)
- Responsive design with CSS styling
- Multilingual support

## Method 2: Custom Form Using Public API

### API Endpoint
Use the public subscription endpoint that doesn't require authentication:
```
POST /api/public/subscription
```

### HTML Form Example
```html
<form action="http://your-listmonk-domain.com/api/public/subscription" method="POST">
    <input type="email" name="email" required placeholder="Email address">
    <input type="text" name="name" placeholder="Name (optional)">
    <!-- Replace LIST_UUID_HERE with your actual list UUID -->
    <input type="hidden" name="l" value="LIST_UUID_HERE">
    <button type="submit">Subscribe</button>
</form>
```

### JavaScript/Fetch Example
```javascript
async function subscribeUser(email, name, listUuids) {
    try {
        const response = await fetch('http://your-listmonk-domain.com/api/public/subscription', {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                // Add CORS headers if needed
            },
            body: JSON.stringify({
                email: email,
                name: name,
                list_uuids: listUuids
            })
        });
        
        const result = await response.json();
        if (result.data === true) {
            console.log('Subscription successful!');
            return true;
        }
    } catch (error) {
        console.error('Subscription failed:', error);
        return false;
    }
}

// Usage
subscribeUser('user@example.com', 'User Name', ['your-list-uuid-here']);
```

### Form Data vs JSON
The API accepts both form-encoded and JSON data:

**Form-encoded (use `l` for multiple lists):**
```bash
curl 'http://your-listmonk-domain.com/api/public/subscription' \
    -d 'email=user@example.com' \
    -d 'name=User Name' \
    -d 'l=list-uuid-1' \
    -d 'l=list-uuid-2'
```

**JSON format:**
```bash
curl 'http://your-listmonk-domain.com/api/public/subscription' \
    -H 'Content-Type: application/json' \
    -d '{"email":"user@example.com","name":"User Name","list_uuids":["list-uuid-1","list-uuid-2"]}'
```

## Email Automation & Triggers

### Understanding List Types & Opt-in Behavior

Listmonk supports two types of lists that determine email automation behavior:

#### 1. Single Opt-in Lists
- Subscribers are immediately added with `unconfirmed` status
- They receive campaign emails right away
- No confirmation email required
- Best for internal lists or when explicit consent was already obtained

#### 2. Double Opt-in Lists
- Subscribers are added with `unconfirmed` status
- **Automatic confirmation email is sent** using the `subscriber-optin.html` template
- Subscribers must click the confirmation link to receive campaigns
- Status changes to `confirmed` after clicking the link
- Provides explicit consent and reduces spam complaints

### Triggering Emails from Your Website

#### Method 1: Transactional Emails (Recommended for Welcome Messages)

Use the `/api/tx` endpoint to send immediate emails when someone signs up:

```javascript
async function signupWithWelcomeEmail(email, name, listUuids, templateId) {
    // Step 1: Add subscriber
    const subscribeResponse = await fetch('http://your-listmonk-domain.com/api/public/subscription', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            email: email,
            name: name,
            list_uuids: listUuids
        })
    });

    if (subscribeResponse.ok) {
        // Step 2: Send immediate welcome email
        const emailResponse = await fetch('http://your-listmonk-domain.com/api/tx', {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Basic ' + btoa('api_username:api_password')
            },
            body: JSON.stringify({
                subscriber_email: email,
                template_id: templateId, // Your welcome email template ID
                data: {
                    welcome_message: "Thanks for joining!",
                    signup_date: new Date().toISOString()
                }
            })
        });
        
        return { subscribed: true, emailSent: emailResponse.ok };
    }
    return { subscribed: false, emailSent: false };
}
```

**Setup Requirements:**
1. Create a **Transactional Template** in Listmonk admin
2. Create API credentials (see section below)
3. Use the template ID in your API calls

### Getting API Credentials

To use the transactional email and campaign APIs, you need to create API credentials:

#### Step 1: Access Users Management
1. Login to your Listmonk admin dashboard
2. Go to **Settings** → **Users** (in the left sidebar)

#### Step 2: Create an API User
1. Click the **"New"** button
2. Select **"API"** user type (not "User")
3. Enter a **username** (this will be your API username)
   - Example: `api_user`, `website_api`, `transactional_api`
4. Enter a **name** (optional, for identification)
5. Set **status** to "Enabled"
6. Click **"Save"**

#### Step 3: Get Your API Password
After creating the API user, Listmonk will display a **randomly generated password/token**. This is shown **only once**, so:

1. **Copy the password immediately** - you won't see it again
2. Store it securely (password manager, environment variables, etc.)
3. This password is what you'll use in your API calls

#### Step 4: Use in Your Code
Replace the placeholder values in your code:

```javascript
// Replace these with your actual values
const API_USERNAME = 'your_api_username';  // From step 3
const API_PASSWORD = 'your_generated_token';  // From step 3 (copy immediately!)

// Use in Authorization header
'Authorization': 'Basic ' + btoa(`${API_USERNAME}:${API_PASSWORD}`)
```

#### Security Notes:
- **Never commit API credentials to version control**
- Store credentials in environment variables:
  ```javascript
  const API_USERNAME = process.env.LISTMONK_API_USER;
  const API_PASSWORD = process.env.LISTMONK_API_TOKEN;
  ```
- API users can only access API endpoints, not the admin dashboard
- You can disable/delete API users anytime from the Users page

#### Method 2: Start Pre-created Campaigns

Create a campaign and trigger it programmatically:

```javascript
async function triggerWelcomeCampaign(campaignId) {
    const response = await fetch(`http://your-listmonk-domain.com/api/campaigns/${campaignId}/status`, {
        method: 'PUT',
        headers: { 
            'Content-Type': 'application/json',
            'Authorization': 'Basic ' + btoa('api_username:api_password')
        },
        body: JSON.stringify({
            status: "running"
        })
    });
    
    return response.ok;
}
```

#### Method 3: Double Opt-in Confirmation Email (Automatic)
When you add subscribers to a **double opt-in list**, Listmonk automatically sends a confirmation email using the template at `/static/email-templates/subscriber-optin.html`.

**To customize the confirmation email:**
1. Edit `/static/email-templates/subscriber-optin.html`
2. Modify the text, styling, and branding to match your needs
3. The template includes variables like `{{ .Subscriber.FirstName }}`, `{{ .OptinURL }}`, etc.

### Getting Your List UUIDs

To find your list UUIDs needed for forms:

1. **Via Admin Dashboard:**
   - Login to your Listmonk admin panel
   - Go to Lists section
   - Click on a list to see its UUID in the URL or details

2. **Via API (if you have admin access):**
   ```bash
   curl -u 'username:password' 'http://your-listmonk-domain.com/api/lists'
   ```

## Best Practices

### Security & Privacy
- Always validate email addresses on both client and server side
- Consider implementing rate limiting on your forms
- Add CAPTCHA for public forms to prevent spam
- Comply with GDPR/privacy regulations in your region
- Use HTTPS for all form submissions

### User Experience
- Provide clear feedback after form submission
- Set proper expectations about confirmation emails
- Make unsubscribe process easy and visible
- Consider progressive enhancement for JavaScript-dependent features

### Email Deliverability
- Use double opt-in for better deliverability and compliance
- Configure proper SPF, DKIM, and DMARC records
- Monitor bounce rates and handle bounces appropriately
- Keep your subscriber lists clean and engaged

## Example Complete Integration

Here's a complete example with proper error handling:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Subscribe to Our Newsletter</title>
</head>
<body>
    <form id="subscription-form">
        <h2>Subscribe to Our Newsletter</h2>
        <div>
            <label for="email">Email Address *</label>
            <input type="email" id="email" name="email" required>
        </div>
        <div>
            <label for="name">Name</label>
            <input type="text" id="name" name="name">
        </div>
        <button type="submit">Subscribe</button>
        <div id="message"></div>
    </form>

    <script>
    document.getElementById('subscription-form').addEventListener('submit', async function(e) {
        e.preventDefault();
        
        const email = document.getElementById('email').value;
        const name = document.getElementById('name').value;
        const messageDiv = document.getElementById('message');
        
        try {
            const response = await fetch('http://your-listmonk-domain.com/api/public/subscription', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    email: email,
                    name: name,
                    list_uuids: ['your-list-uuid-here'] // Replace with your actual UUID
                })
            });
            
            const result = await response.json();
            
            if (result.data === true) {
                messageDiv.innerHTML = '<p style="color: green;">✅ Subscription successful! Please check your email for confirmation.</p>';
                document.getElementById('subscription-form').reset();
            } else {
                messageDiv.innerHTML = '<p style="color: red;">❌ Subscription failed. Please try again.</p>';
            }
        } catch (error) {
            messageDiv.innerHTML = '<p style="color: red;">❌ Network error. Please try again later.</p>';
        }
    });
    </script>
</body>
</html>
```

## Troubleshooting

### Common Issues
- **CORS errors**: Configure your Listmonk server to allow cross-origin requests from your domain
- **UUID not found**: Verify your list UUIDs are correct and the lists exist
- **Emails not sending**: Check your SMTP configuration and email templates
- **Form not submitting**: Verify the API endpoint URL and check browser console for errors

### Testing
- Test form submission with both valid and invalid email addresses
- Verify confirmation emails are being sent and received
- Check that subscribers appear in your admin dashboard
- Test unsubscribe links work properly