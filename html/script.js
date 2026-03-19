let currentCategory = 'items';
let shopData = {};
let isNight = false;
let selectedItem = null;
let playerMoney = 0;

// Get resource name - store it immediately to avoid recursion
const resourceName = (function() {
    if (window.invokeNative) {
        return window.GetParentResourceName ? window.GetParentResourceName() : 'phils-travmerchant';
    }
    return 'phils-travmerchant';
})();

// Category icons mapping
const categoryIcons = {
    items: 'fa-solid fa-drumstick-bite',
    herbs: 'fa-solid fa-leaf',
    weapons: 'fa-solid fa-crosshairs',
    alcohol: 'fa-solid fa-whiskey-glass'
};

// Listen for NUI messages from client
window.addEventListener('message', function(event) {
    const data = event.data;
    
    switch(data.action) {
        case 'openShop':
            openShop(data);
            break;
        case 'closeShop':
            closeShop();
            break;
        case 'updateMoney':
            updateMoney(data.money);
            break;
        case 'purchaseResult':
            handlePurchaseResult(data.success, data.message);
            break;
    }
});

function openShop(data) {
    shopData = {
        items: data.items || {},
        herbs: data.herbs || {},
        weapons: data.weapons || {},
        alcohol: data.alcohol || {}
    };
    isNight = data.isNight || false;
    playerMoney = data.money || 0;
    
    document.getElementById('merchant-container').classList.remove('hidden');
    updateMoney(playerMoney);
    
    // Update time indicator
    updateTimeIndicator();
    
    // Update tab availability based on time
    updateTabsForTime();
    
    // Show appropriate default category
    if (isNight) {
        switchCategory('weapons');
    } else {
        switchCategory('items');
    }
}

function closeShop() {
    document.getElementById('merchant-container').classList.add('hidden');
    closePurchaseModal();
    fetch(`https://${resourceName}/closeUI`, {
        method: 'POST',
        body: JSON.stringify({})
    });
}

function updateMoney(amount) {
    playerMoney = amount;
    document.getElementById('player-money').textContent = '$' + playerMoney.toFixed(2);
}

function updateTimeIndicator() {
    const indicator = document.getElementById('time-indicator');
    const icon = document.getElementById('time-icon');
    const text = document.getElementById('time-text');
    
    if (isNight) {
        indicator.classList.remove('day');
        indicator.classList.add('night');
        icon.className = 'fa-solid fa-moon';
        text.textContent = 'Nighttime';
    } else {
        indicator.classList.remove('night');
        indicator.classList.add('day');
        icon.className = 'fa-solid fa-sun';
        text.textContent = 'Daytime';
    }
}

function updateTabsForTime() {
    const tabs = document.querySelectorAll('.tab-btn');
    tabs.forEach(tab => {
        const category = tab.dataset.category;
        const isAvailable = isNight 
            ? (category === 'weapons' || category === 'alcohol')
            : (category === 'items' || category === 'herbs');
        
        tab.classList.toggle('disabled', !isAvailable);
    });
}

function switchCategory(category) {
    currentCategory = category;
    
    // Update active tab
    document.querySelectorAll('.tab-btn').forEach(tab => {
        tab.classList.toggle('active', tab.dataset.category === category);
    });
    
    // Update time banner
    const banner = document.getElementById('time-banner');
    const bannerText = document.getElementById('time-banner-text');
    const isAvailable = isNight 
        ? (category === 'weapons' || category === 'alcohol')
        : (category === 'items' || category === 'herbs');
    
    if (!isAvailable) {
        banner.classList.remove('hidden');
        if (isNight) {
            bannerText.textContent = 'These wares are only available during the day';
        } else {
            bannerText.textContent = 'These wares are only available at night';
        }
    } else {
        banner.classList.add('hidden');
    }
    
    // Clear search
    document.getElementById('search-input').value = '';
    
    // Render items
    renderItems();
}

function renderItems(filter) {
    const grid = document.getElementById('items-grid');
    const items = shopData[currentCategory] || {};
    const filterLower = (filter || '').toLowerCase();
    
    const isAvailable = isNight 
        ? (currentCategory === 'weapons' || currentCategory === 'alcohol')
        : (currentCategory === 'items' || currentCategory === 'herbs');
    
    let html = '';
    let count = 0;
    
    for (const [itemName, itemData] of Object.entries(items)) {
        const label = itemData.label || itemName;
        
        // Filter check
        if (filterLower && !label.toLowerCase().includes(filterLower)) {
            continue;
        }
        
        count++;
        html += `
            <div class="item-card ${!isAvailable ? 'unavailable' : ''}" 
                 data-item="${itemName}" 
                 data-category="${currentCategory}"
                 data-price="${itemData.price}"
                 data-label="${label}">
                <i class="item-card-icon ${categoryIcons[currentCategory]}"></i>
                <div class="item-name">${label}</div>
                <div class="item-price">
                    <i class="fa-solid fa-dollar-sign"></i>
                    ${itemData.price}
                </div>
                ${!isAvailable ? `
                    <span class="item-restricted">
                        <i class="fa-solid fa-lock"></i>
                        ${isNight ? 'Day Only' : 'Night Only'}
                    </span>
                ` : ''}
            </div>
        `;
    }
    
    if (count === 0) {
        html = `
            <div class="empty-state">
                <i class="fa-solid fa-box-open"></i>
                <p>${filter ? 'No items match your search' : 'No wares available in this category'}</p>
            </div>
        `;
    }
    
    grid.innerHTML = html;
    
    // Add click handlers to available items
    grid.querySelectorAll('.item-card:not(.unavailable)').forEach(card => {
        card.addEventListener('click', function() {
            openPurchaseModal(this);
        });
    });
    
    // Unavailable items click - show notification
    grid.querySelectorAll('.item-card.unavailable').forEach(card => {
        card.addEventListener('click', function() {
            showNotification(
                isNight ? 'This item is only available during the day' : 'This item is only available at night',
                'error'
            );
        });
    });
}

function openPurchaseModal(card) {
    selectedItem = {
        name: card.dataset.item,
        category: card.dataset.category,
        price: parseFloat(card.dataset.price),
        label: card.dataset.label
    };
    
    document.getElementById('modal-item-name').textContent = selectedItem.label;
    document.getElementById('modal-price').textContent = '$' + selectedItem.price.toFixed(2);
    document.getElementById('modal-icon').className = categoryIcons[selectedItem.category];
    document.getElementById('quantity-input').value = 1;
    updateTotal();
    
    document.getElementById('purchase-modal').classList.remove('hidden');
}

function closePurchaseModal() {
    document.getElementById('purchase-modal').classList.add('hidden');
    selectedItem = null;
}

function updateTotal() {
    if (!selectedItem) return;
    const qty = parseInt(document.getElementById('quantity-input').value) || 1;
    const total = selectedItem.price * qty;
    document.getElementById('modal-total').textContent = '$' + total.toFixed(2);
}

function adjustQuantity(delta) {
    const input = document.getElementById('quantity-input');
    let value = parseInt(input.value) || 1;
    value = Math.max(1, Math.min(100, value + delta));
    input.value = value;
    updateTotal();
}

function setQuantity(qty) {
    document.getElementById('quantity-input').value = qty;
    updateTotal();
}

function confirmPurchase() {
    if (!selectedItem) return;
    
    const qty = parseInt(document.getElementById('quantity-input').value) || 1;
    const total = selectedItem.price * qty;
    
    // Check if player has enough money
    if (total > playerMoney) {
        showNotification('You don\'t have enough money', 'error');
        return;
    }
    
    const isWeapon = selectedItem.category === 'weapons';
    
    fetch(`https://${resourceName}/purchase`, {
        method: 'POST',
        body: JSON.stringify({
            item: selectedItem.name,
            quantity: qty,
            isWeapon: isWeapon
        })
    });
    
    closePurchaseModal();
}

function handlePurchaseResult(success, message) {
    showNotification(message, success ? 'success' : 'error');
}

function showNotification(message, type) {
    const container = document.getElementById('notification-container');
    
    const notif = document.createElement('div');
    notif.className = 'notification ' + (type || 'info');
    
    let icon = 'fa-circle-info';
    if (type === 'success') icon = 'fa-circle-check';
    if (type === 'error') icon = 'fa-circle-xmark';
    
    notif.innerHTML = '<i class="fa-solid ' + icon + '"></i><span>' + message + '</span>';
    container.appendChild(notif);
    
    setTimeout(function() {
        notif.classList.add('fade-out');
        setTimeout(function() {
            if (notif.parentNode) {
                notif.parentNode.removeChild(notif);
            }
        }, 300);
    }, 3000);
}

// Initialize event listeners when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    // Tab clicks
    var tabs = document.querySelectorAll('.tab-btn');
    for (var i = 0; i < tabs.length; i++) {
        tabs[i].addEventListener('click', function() {
            if (this.classList.contains('disabled')) {
                showNotification(
                    isNight ? 'These wares are only available during the day' : 'These wares are only available at night',
                    'error'
                );
                return;
            }
            switchCategory(this.dataset.category);
        });
    }
    
    // Close shop button
    document.getElementById('close-shop').addEventListener('click', closeShop);
    
    // Modal close button
    document.querySelector('.modal-close').addEventListener('click', closePurchaseModal);
    
    // Cancel button
    document.querySelector('.btn-cancel').addEventListener('click', closePurchaseModal);
    
    // Purchase button
    document.getElementById('confirm-purchase').addEventListener('click', confirmPurchase);
    
    // Quantity minus button
    document.querySelector('.qty-btn.minus').addEventListener('click', function() {
        adjustQuantity(-1);
    });
    
    // Quantity plus button
    document.querySelector('.qty-btn.plus').addEventListener('click', function() {
        adjustQuantity(1);
    });
    
    // Quantity input change
    document.getElementById('quantity-input').addEventListener('input', updateTotal);
    
    // Quick quantity buttons
    var quickBtns = document.querySelectorAll('.quick-btn');
    for (var j = 0; j < quickBtns.length; j++) {
        quickBtns[j].addEventListener('click', function() {
            setQuantity(parseInt(this.dataset.qty));
        });
    }
    
    // Close modal on overlay click
    document.querySelector('.modal-overlay').addEventListener('click', closePurchaseModal);
    
    // Search functionality
    document.getElementById('search-input').addEventListener('input', function() {
        renderItems(this.value);
    });
    
    // ESC key to close
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            var modal = document.getElementById('purchase-modal');
            var container = document.getElementById('merchant-container');
            
            if (!modal.classList.contains('hidden')) {
                closePurchaseModal();
            } else if (!container.classList.contains('hidden')) {
                closeShop();
            }
        }
    });
});