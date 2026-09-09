import assert from "node:assert/strict";

// Check the content, not just the outer dialog or compact consent row.
export async function assertReporterFormLayout(page) {
  const metrics = await page.locator('[data-handrail-bug-report-form]').evaluate(form => {
    const fits = element => element.scrollWidth <= element.clientWidth + 1;
    const content = form.closest('[data-handrail-bug-reporter-content]');
    const containers = [content,
      form.querySelector('[data-handrail-bug-report-layout]'),
      form.querySelector('[data-handrail-bug-report-details]')];
    return {
      containersFit: containers.every(fits),
      // The footer intentionally extends into the content's horizontal padding.
      formFitsContent: form.getBoundingClientRect().left + form.scrollWidth <=
        content.getBoundingClientRect().right + 1,
      labels: [...form.querySelectorAll('[data-handrail-bug-report-details] label')].map(label => {
        const input = label.querySelector('input, select, textarea');
        const bounds = label.getBoundingClientRect();
        const field = input.getBoundingClientRect();
        const heading = label.querySelector('span');
        const css = getComputedStyle(label);
        return {
          before: getComputedStyle(label, '::before').content,
          after: getComputedStyle(label, '::after').content,
          fits: fits(label) && fits(input),
          width: field.width,
          fillsLabel: Math.abs(field.width - bounds.width) <= 1,
          belowHeading: field.top > bounds.top,
          typography: { size: css.fontSize, weight: css.fontWeight,
            align: css.textAlign, gap: css.gap },
          heading: heading && {
            size: getComputedStyle(heading).fontSize,
            transform: getComputedStyle(heading).textTransform,
            wraps: getComputedStyle(heading).whiteSpace,
            optionalSize: getComputedStyle(heading.querySelector('span')).fontSize,
            optionalWeight: getComputedStyle(heading.querySelector('span')).fontWeight,
          },
        };
      }),
    };
  });
  assert.equal(metrics.containersFit, true, 'form and scroll containers fit horizontally');
  assert.equal(metrics.formFitsContent, true, 'form including footer fits the content width');
  assert.equal(metrics.labels.length, 4);
  for (const label of metrics.labels) {
    assert.equal(label.before, 'none', 'host label content must not enter the form');
    assert.equal(label.after, 'none');
    assert.equal(label.fits, true, 'label and input must not overflow');
    assert.ok(label.width >= 150, 'fields remain readable at desktop and mobile widths');
    assert.equal(label.fillsLabel, true, 'field uses the full label width');
    assert.equal(label.belowHeading, true, 'heading remains above its field');
    assert.deepEqual(label.typography, { size: '13px', weight: '700', align: 'start', gap: '5px' });
  }
  assert.deepEqual(metrics.labels[3].heading, {
    size: '13px', transform: 'none', wraps: 'normal', optionalSize: '11px', optionalWeight: '500',
  });
  return metrics;
}
