// ============================================================
// Configuration — Replace with your actual API Gateway URL
// ============================================================
const API_BASE_URL = "https://[ADD YOUR URL HERE].amazonaws.com/prod";

// Generate or retrieve a simple persistent user ID
const USER_ID = (() => {
  let id = localStorage.getItem("recipeUserId");
  if (!id) {
    id = "user_" + Math.random().toString(36).substring(2, 11);
    localStorage.setItem("recipeUserId", id);
  }
  return id;
})();

// ============================================================
// State
// ============================================================
let ingredients = [];

// ============================================================
// Ingredient Management
// ============================================================
function addIngredient() {
  const input = document.getElementById("ingredient-input");
  const value = input.value.trim().toLowerCase();

  if (!value) return;
  if (ingredients.includes(value)) {
    showInputError("Ingredient already added.");
    return;
  }
  if (ingredients.length >= 20) {
    showInputError("Maximum 20 ingredients allowed.");
    return;
  }

  ingredients.push(value);
  input.value = "";
  input.focus();
  renderTags();
  updateSuggestButton();
}

function removeIngredient(index) {
  ingredients.splice(index, 1);
  renderTags();
  updateSuggestButton();
}

function renderTags() {
  const container = document.getElementById("ingredient-tags");
  container.innerHTML = ingredients
    .map((ing, i) => `
      <span class="tag">
        ${escapeHtml(ing)}
        <button onclick="removeIngredient(${i})" title="Remove">✕</button>
      </span>
    `)
    .join("");
}

function updateSuggestButton() {
  document.getElementById("suggest-btn").disabled = ingredients.length === 0;
}

function showInputError(msg) {
  const input = document.getElementById("ingredient-input");
  input.setCustomValidity(msg);
  input.reportValidity();
  setTimeout(() => input.setCustomValidity(""), 2500);
}

// Allow pressing Enter to add an ingredient
document.getElementById("ingredient-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") addIngredient();
});

// ============================================================
// Recipe Generation
// ============================================================
async function getSuggestions() {
  if (ingredients.length === 0) return;

  showSection("loading-section");
  hideSection("results-section");

  try {
    const response = await fetch(`${API_BASE_URL}/recipes`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ingredients, userId: USER_ID }),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Unknown error");
    }

    displayRecipe(data.recipe);
    loadHistory(); // Refresh history after new result

  } catch (err) {
    console.error("Error:", err);
    displayError(err.message);
  } finally {
    hideSection("loading-section");
  }
}

function displayRecipe(recipeText) {
  document.getElementById("recipe-output").textContent = recipeText;
  showSection("results-section");
}

function displayError(message) {
  document.getElementById("recipe-output").innerHTML =
    `<span style="color:#e53e3e">⚠️ Error: ${escapeHtml(message)}</span>`;
  showSection("results-section");
}

// ============================================================
// History
// ============================================================
async function loadHistory() {
  const container = document.getElementById("history-list");

  try {
    const response = await fetch(
      `${API_BASE_URL}/history?userId=${encodeURIComponent(USER_ID)}`
    );
    const data = await response.json();
    const history = data.history || [];

    if (history.length === 0) {
      container.innerHTML = '<p class="empty-state">No history yet. Generate your first recipe!</p>';
      return;
    }

    container.innerHTML = history
      .map((item) => {
        const date = new Date(item.timestamp).toLocaleString();
        const ings = (item.ingredients || []).join(", ");
        return `
          <div class="history-item" onclick="showHistoryItem(this)" 
               data-recipe="${escapeHtml(item.recipe)}">
            <div class="date">🕐 ${date}</div>
            <div class="ingredients">🥗 ${escapeHtml(ings)}</div>
          </div>
        `;
      })
      .join("");

  } catch (err) {
    console.error("History load error:", err);
    container.innerHTML = '<p class="empty-state">Could not load history.</p>';
  }
}

function showHistoryItem(el) {
  const recipe = el.getAttribute("data-recipe");
  displayRecipe(recipe);
  document.getElementById("results-section").scrollIntoView({ behavior: "smooth" });
}

// ============================================================
// UI Helpers
// ============================================================
function resetForm() {
  ingredients = [];
  renderTags();
  updateSuggestButton();
  hideSection("results-section");
  document.getElementById("ingredient-input").focus();
}

function showSection(id) {
  document.getElementById(id).classList.remove("hidden");
}

function hideSection(id) {
  document.getElementById(id).classList.add("hidden");
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ============================================================
// Init
// ============================================================
window.addEventListener("DOMContentLoaded", () => {
  loadHistory();
});